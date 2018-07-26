#!/bin/bash
# this test checks that old (v1, pre 8.34.0) imfile state files are
# properly read in. It is based on imfile-readmode2-with-persists.sh,
# where the first part before the shutdown is removed, and an old state
# file is populated. Note that in contrast to the original test the
# initial set of lines from the input file is missing - this is
# exactly what shall happen.
# This is part of the rsyslog testbench, licensed under ASL 2.0
# added 2018-03-29 by rgerhards
. $srcdir/diag.sh init
generate_conf
add_conf '
global(workDirectory="test-spool")
module(load="../plugins/imfile/.libs/imfile")

input(type="imfile"
      File="./rsyslog.input"
      Tag="file:"
      ReadMode="2")

template(name="outfmt" type="list") {
  constant(value="HEADER ")
  property(name="msg" format="json")
  constant(value="\n")
}

if $msg contains "msgnum:" then
 action(
   type="omfile"
   file="rsyslog.out.log"
   template="outfmt"
 )
'
. $srcdir/diag.sh check-inotify

# do mock-up setup
echo 'msgnum:0
 msgnum:1' > rsyslog.input
echo 'msgnum:2' >> rsyslog.input

# we need to patch the state file to match the current inode number
inode=$(ls -i rsyslog.input|awk '{print $1}')
leninode=${#inode}
newline="+inode:2:${leninode}:${inode}:"

sed s/+inode:2:7:4464465:/${newline}/ <$srcdir/testsuites/imfile-old-state-file_imfile-state_.-rsyslog.input > test-spool/imfile-state\:.-rsyslog.input
printf "info: new input file: $(ls -i rsyslog.input)\n"
printf "info: new inode line: ${newline}\n"
printf "info: patched state file:\n"
cat test-spool/imfile-state\:.-rsyslog.input

startup

echo 'msgnum:3
 msgnum:4' >> rsyslog.input
echo 'msgnum:5' >> rsyslog.input

shutdown_when_empty # shut down rsyslogd when done processing messages
wait_shutdown    # we need to wait until rsyslogd is finished!

NUMLINES=$(grep -c HEADER rsyslog.out.log 2>/dev/null)

if [ -z $NUMLINES ]; then
  echo "ERROR: expecting at least a match for HEADER, maybe rsyslog.out.log wasn't even written?"
  cat ./rsyslog.out.log
  error_exit 1
else
  # note: we expect only 2 headers as the first file part if NOT processed!
  if [ ! $NUMLINES -eq 2 ]; then
    echo "ERROR: expecting 2 headers, got $NUMLINES"
    cat ./rsyslog.out.log
    error_exit 1
  fi
fi

## check if all the data we expect to get in the file is there

for i in {2..4}; do
  grep msgnum:$i rsyslog.out.log > /dev/null 2>&1
  if [ ! $? -eq 0 ]; then
    echo "ERROR: expecting the string 'msgnum:$i', it's not there"
    cat ./rsyslog.out.log
    error_exit 1
  fi
done

exit_test
