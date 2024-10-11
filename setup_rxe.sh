#!/bin/bash

set -e

[[ -f rxe/.rxe_setup_complete ]] && exit 0;

RXE_TARGET=${RXE_TARGET:="UNKNOWN"}

if [[ "${RXE_TARGET}" == "UNKNOWN" ]]; then
	if [[ -f /etc/os-release ]]; then
		rel=$(cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2 | sed -e s~\"~~g)
	else
		rel=$(lsb_release -d -s | sed -e s~\"~~g)
	fi
	# SLES15 returns a string with quotes for whatever reason.
	if [[ "$rel" = "SUSE Linux Enterprise Server 15 SP4" ]]; then
		RXE_TARGET=SLES_15_SP4
	elif [[ "$rel" = "SUSE Linux Enterprise Server 15 SP5" ]]; then
		RXE_TARGET=SLES_15_SP5
	elif [[ "$rel" = "Rocky Linux 9.2 (Blue Onyx)" ]]; then
		RXE_TARGET=ROCKY_9_2
	elif [[ "$rel" = "Red Hat Enterprise Linux 9.4 (Plow)" ]]; then
		RXE_TARGET=RHEL_9_4
	else
	    echo "Unrecognized target $rel, set RXE_TARGET"
	    rm -rf rxe
	    mkdir -p rxe;
	    touch rxe/Makefile
	    exit 0
	fi
fi

tarball=rxe-6.3.tar.gz

if [[ "${RXE_TARGET}" = "SLES_15_SP4" ]]; then
    export QUILT_SERIES=SLES-15-SP4.series
    compatibility_files="common.series sles15_sp5_compatibility.series sles15_sp4_compatibility.series"
elif [[ "${RXE_TARGET}" = "SLES_15_SP5" ]]; then
    export QUILT_SERIES=SLES-15-SP5.series
    compatibility_files="common.series sles15_sp5_compatibility.series"
elif [[ "${RXE_TARGET}" = "ROCKY_9_2" ]]; then
    export QUILT_SERIES=ROCKY_9_2.series
    compatibility_files="common.series rocky9.2_compatibility.series"
elif [[ "${RXE_TARGET}" = "RHEL_9_4" ]]; then
    export QUILT_SERIES=RHEL_9_4.series
    compatibility_files=""
else
    echo "No patch series found for target ${RXE_TARGET}"
    rm -rf rxe
    mkdir -p rxe;
    touch rxe/Makefile
    exit 0
fi

echo "Build for ${RXE_TARGET}"
echo "Version = ${VER_STR}"
echo "Quilt Series = $QUILT_SERIES"

cat patches/upstream/upstream.series > patches/${QUILT_SERIES}
cat patches/functionality/functionality.series >> patches/${QUILT_SERIES}
for f in ${compatibility_files}; do
	cat patches/compatibility/${f} >> patches/${QUILT_SERIES}
done

tar -xzf $tarball
echo "#define RXE_VERSION_STRING \"${VER_STR}\"" > rxe/rxe_ver_str.h

quilt push -a && touch rxe/.rxe_setup_complete
