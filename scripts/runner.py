#!/usr/bin/env python3

# Copyright (C) 2019  Braiins Systems s.r.o.
#
# This file is part of Braiins Open-Source Initiative (BOSI).
#
# BOSI is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# Please, keep in mind that we may also license BOSI or any part thereof
# under a proprietary license. For more information on the terms and conditions
# of such proprietary license or if you have any other questions, please
# contact us at opensource@braiins.com.

"""
This is a small helper script to take care of deployment and firing up
of compiled binaries and tests onto target device used for testing.
Basicaly it takes a file given as first arg, copies it onto device specified
in config file or as additional argument, runs it, and returns its return code.
It is intended to be used as a custom runner in cargo config for crosscompiled
parts of project.
ssh & scp does all the legwork, openwrt's "lock" is used to handle concurrency
and --test-threads 1 is passed to commands that look like a cargo tests.
Unrecognized args are passed along to target binary.
"""

import sys
import os.path
import re
import argparse
import toml
import subprocess
import shutil

CONFIG_FILE = 'Test.toml'
DEFAULT_USER = 'root'
CONFIG_PATHS = ['.', '..']


def main():
    parser = argparse.ArgumentParser(__doc__)

    parser.add_argument('test',
                        help='Path to executable with the test.')
    parser.add_argument('--apply', metavar='COMMAND',
                        help="Run command on input file. Path to test will replace string '{}' or be appended.")
    parser.add_argument('--compress', action='store_true',
                        help='Compress file before transfer.')
    arg_hostname = parser.add_argument('--hostname',
                        help='Ip address or hostname of remote bOS device with ssh server.')
    parser.add_argument('--keep', action='store_true',
                        help='Keep remote file.')
    parser.add_argument('--path', dest='host_path', default='/tmp', metavar='PATH',
                        help='Target path on remote host.')
    parser.add_argument('--user',
                        help='Remote login user.')
    parser.add_argument('--verbose', action='store_true',
                        help='Log commands to stdout.')

    # parse command line arguments
    (args, extra_args) = parser.parse_known_args()

    runner = run_verbose if args.verbose else run_silent

    cfg_user = None
    cfg_hostname = None

    # construct all config file locations
    cfg_locations = [os.path.join(dir, CONFIG_FILE) for dir in CONFIG_PATHS]
    cfg_path = next((path for path in cfg_locations if os.path.isfile(path)), None)

    if cfg_path is not None:
        # try to get default configuration from configuration file
        config = toml.load(cfg_path)
        remote = config.get('remote')
        if remote:
            cfg_user = remote.get('user')
            cfg_hostname = remote.get('hostname')

    # get remote settings
    user = args.user or cfg_user or DEFAULT_USER
    hostname = args.hostname or cfg_hostname

    if not hostname:
        parser.error("Missing remote hostname which can be specified by '{}' argument or in '{}'"
              .format(arg_hostname.option_strings[0], CONFIG_FILE))

    test_path = args.test
    test_name = os.path.basename(args.test)
    # stuff resembling cargo tests (file ends with a dash followed by sixteen hex digits)
    # is automagically endowed with param to enforce single thread to ensure exclusive access to hw
    remote_argv = ['--test-threads', '1'] if re.match('.+-[0-9a-f]{16}$', args.test) else []
    remote_argv += extra_args
    remote_test = os.path.join(args.host_path, test_name)
    common_args = ['-o', 'StrictHostKeyChecking=no']

    if args.apply:
        test_path = shutil.copy(args.test, '/tmp')
        deleter = Deleter(test_path)
        command = args.apply.replace('{}', test_path) if '{}' in args.apply else args.apply + ' ' + test_path
        runner(
            command,
            shell=True,
            check=True,
        )

    if args.compress:
        runner(
            'gzip',
            '--keep',
            '--force',
            test_path
        )
        compression_suffix = '.gz'
    else:
        compression_suffix = ''


    if not args.verbose:
        # suppress message 'Connection to XYZ closed.'
        common_args.append('-q')

    # create target dir if not exist and acquire a lock, in case multiple runners meet.
    # note this locking is openwrt specific, and unlike flock have to be explicitely unlocked
    run_lock = runner(
        'ssh',
        *common_args,
        '-l', user,
        hostname,
        'mkdir -p ' + args.host_path + ' && lock /tmp/testrunner',
        check=True,
    )

    try:
        if args.verbose:
            print('copying %d bytes' % os.path.getsize(test_path))
        cpy_ret = runner(
            'scp',
            '-q',   # no progressbar
            '-C',   # enable compression
            *common_args,
            test_path + compression_suffix,
            '{}@{}:{}'.format(user, hostname, args.host_path),
            check=True,
        )

        if args.compress:
            run_dec = runner(
                'ssh',
                *common_args,
                '-l', user,
                hostname,
                'gunzip ' + remote_test + compression_suffix,
                check=True,
            )

        run_ret = runner(
            'ssh',
            *common_args,
            '-t',   # force pty
            '-l', user,
            hostname,
            remote_test + ' ' + ' '.join(remote_argv),
            check=False,
        )

    finally:
        # clean up code and lock
        clean_ret = runner(
            'ssh',
            *common_args,
            '-l', user,
            hostname,
            ('rm -f ' + remote_test + ' ; ' if not args.keep else '') + 'lock -u /tmp/testrunner',
            check=True,
        )

    sys.exit(run_ret.returncode)


def run_silent(*args, **kargs):
    """wrapper over subprocess for nicer call format"""
    return subprocess.run(args, **kargs)


def run_verbose(*args, **kargs):
    """wrap subprocess.run to log executed commands on stdout"""
    print(' '.join(args), flush=True)
    return run_silent(*args, **kargs)

class Deleter:
    def __init__(self, path):
        self.path = path

    def __del__(self):
        os.unlink(self.path)


if __name__ == "__main__":
    # execute only if run as a script
    main()
