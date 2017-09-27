#!/bin/bash
set -e
if [ ! -r "$1" ]; then
	echo "Usage: $0 <file>"
	exit 1
fi
TFILE=`mktemp`
hexdump -v -f `dirname $0`/rezhex.format "$1" | tr 'Q' '"' > $TFILE
cat << EOF
type 'BBLK' {
   hex string;
};

resource 'BBLK' (5120, "Apple //e Boot Blocks") {
`cat $TFILE`
};
EOF
rm -f $TFILE

