#!/bin/bash
#
# Copyright (c) 2006 Mellanox Technologies. All rights reserved.
# Copyright (c) 2004, 2005, 2006 Voltaire, Inc. All rights reserved.
#
# This Software is licensed under one of the following licenses:
#
# 1) under the terms of the "Common Public License 1.0" a copy of which is
#    available from the Open Source Initiative, see
#    http://www.opensource.org/licenses/cpl.php.
#
# 2) under the terms of the "The BSD License" a copy of which is
#    available from the Open Source Initiative, see
#    http://www.opensource.org/licenses/bsd-license.php.
#
# 3) under the terms of the "GNU General Public License (GPL) Version 2" a
#    copy of which is available from the Open Source Initiative, see
#    http://www.opensource.org/licenses/gpl-license.php.
#
# Licensee has the right to choose one of the above licenses.
#
# Redistributions of source code must retain the above copyright
# notice and one of the license notices.
#
# Redistributions in binary form must reproduce both the above copyright
# notice, one of the license notices in the documentation
# and/or other materials provided with the distribution.
#
# Description: creates Module.symvers file for InfiniBand modules 

KVERSION=${KVERSION:-$(uname -r)}
MOD_SYMVERS=../resilience_manager/Module.symvers
SYMS=./syms

MODULES_DIR=/var/lib/dkms/mlnx-ofed-kernel/kernel-$(uname -r)-x86_64/module

if [ -f ${MOD_SYMVERS} -a ! -f ${MOD_SYMVERS}.save ]; then
	mv ${MOD_SYMVERS} ${MOD_SYMVERS}.save
fi
rm -f $MOD_SYMVERS
rm -f $SYMS

for mod in $(find ${MODULES_DIR} -name '*.ko') ; do
           nm -o $mod |grep __crc >> $SYMS
           n_mods=$((n_mods+1))
done

n_syms=$(wc -l $SYMS |cut -f1 -d" ")
echo Found $n_syms OFED kernel symbols in $n_mods modules
n=1

while [ $n -le $n_syms ] ; do
    line=$(head -$n $SYMS|tail -1)

    line1=$(echo $line|cut -f1 -d:)
    line2=$(echo $line|cut -f2 -d:)
    file=$(echo $line1| sed -e 's@./@@' -e 's@.ko@@' -e "s@$PWD/@@")
    crc=$(echo $line2|cut -f1 -d" ")
    sym=$(echo $line2|cut -f3 -d" ")
    echo -e  "0x$crc\t$sym\t$file" >> $MOD_SYMVERS
    n=$((n+1))
done

rm $SYMS
echo ${MOD_SYMVERS} created. 

