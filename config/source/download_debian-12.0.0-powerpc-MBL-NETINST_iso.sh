#!/bin/sh
FILEID="10aiQVrNPxD9Fx1kKEVqRwuS2ZzEfab23"

wget --load-cookies /tmp/cookies.txt "https://docs.google.com/uc?export=download&confirm=$(wget --quiet --save-cookies /tmp/cookies.txt --keep-session-cookies --no-check-certificate 'https://docs.google.com/uc?export=download&id='${FILEID} -O- | sed -rn 's/.*confirm=([0-9A-Za-z_]+).*/\1\n/p')&id=${FILEID}" -O debian-12.0.0-powerpc-MBL-NETINST-1.iso && rm -rf /tmp/cookies.txt

