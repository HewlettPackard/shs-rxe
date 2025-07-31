# Copyright 2021 Hewlett Packard Enterprise Development LP
%define release_extra SHS0.0.0

%{!?dkms_source_tree:%define dkms_source_tree /usr/src}

%if 0%{?rhel}
%define distro_kernel_package_name kmod-%{name}
%else
%define distro_kernel_package_name %{name}-kmp
%endif

Name:           cray-rxe-driver
Version:        5.1.0
Release:        %(echo ${BUILD_METADATA})
Summary:        Soft RoCE Driver
License:        GPLv2
Source0:        %{name}-%{version}.tar.gz
%if 0%{?include_aux_files}
Source1:    kmp_files
Source2:    rxe_versions
%endif
Prefix:         /usr

BuildRequires:  quilt
%if 0%{?sle_version} >= 150200
# Make sure a SLES release file is installed
BuildRequires:  sles-release
%endif
BuildRequires:  %kernel_module_package_buildreqs

%kernel_module_package -f %{_sourcedir}/kmp_files -p %{_sourcedir}/rxe_versions -x preempt

%description
Cray Enhanced Soft RoCE Driver

%package devel
Summary:    Development files for Soft RoCE driver

%description devel
Development files for Cray Enhanced Soft RoCE driver

%package dkms
Summary:        DKMS support for %{name} kernel modules
Requires:   quilt
Requires:       dkms
%if 0%{?sle_version} >= 150200
# Make sure a SLES release file is installed
Requires:   sles-release
%endif
BuildArch:      noarch

%description dkms
DKMS support for %{name} kernel modules

%prep
%setup

set -- *
mkdir source
mv "$@" source/
mkdir obj

%build
for flavor in %flavors_to_build; do
    rm -rf obj/$flavor
    cp -r source obj/$flavor
    TOP=$PWD
    cd $PWD/obj/$flavor/
    VER_STR=%{version} ./setup_rxe.sh
    cd $TOP
    make -C %{kernel_source $flavor} modules M=$PWD/obj/$flavor/rxe %{?_smp_mflags}
done


%install
export INSTALL_MOD_PATH=$RPM_BUILD_ROOT
export INSTALL_MOD_DIR=%kernel_module_package_moddir %{name}
for flavor in %flavors_to_build; do
    make -C %{kernel_source $flavor} modules_install M=$PWD/obj/$flavor/rxe
    install -D $PWD/obj/$flavor/rxe/Module.symvers $RPM_BUILD_ROOT/%{prefix}/src/rxe/$flavor/Module.symvers
    mkdir -p $RPM_BUILD_ROOT/usr/bin
    install -D $PWD/source/scripts/rxe_init.sh -m0764 $RPM_BUILD_ROOT/usr/bin
done

# Remove any test modules (test-atu.ko, test-domain.ko, etc.)that got installed
rm -f $INSTALL_MOD_PATH/%{prefix}/lib/modules/*/$INSTALL_MOD_DIR/test-*.ko

# DKMS addition
dkms_source_dir=%{dkms_source_tree}/%{name}-%{version}-%{release}
mkdir -p %{buildroot}${dkms_source_dir}
cp -r source/* %{buildroot}${dkms_source_dir}

## QUIRK
cp -r ${PWD}/obj/${flavor}/rxe %{buildroot}${dkms_source_dir}
rm -rf %{buildroot}${dkms_source_dir}/patches
rm -f  %{buildroot}${dkms_source_dir}/rxe/*.o
rm -f  %{buildroot}${dkms_source_dir}/rxe/.*.cmd
rm -f  %{buildroot}${dkms_source_dir}/rxe-*.tar.gz

files_to_delete="""
Jenkinsfile
Jenkinsfile.cxi_vm
README
cxi_vm_script.sh
cray-rxe-driver.spec
rxe/Module.symvers
rxe/modules.order
rxe/rdma_rxe.ko
rxe/rdma_rxe.mod
rxe/rdma_rxe.mod.c
set_slingshot_version.sh
setup_rxe.sh
"""

for f in ${files_to_delete}
do
    rm -f %{buildroot}${dkms_source_dir}/${f}
done
## END QUIRK

echo "%dir ${dkms_source_dir}" > dkms-files
echo "${dkms_source_dir}" >> dkms-files

sed\
  -e '/^$/d'\
  -e '/^#/d'\
  -e 's/@PACKAGE_NAME@/%{name}/g'\
  -e 's/@PACKAGE_VERSION@/%{version}-%{release}/g'\
\
  %{buildroot}${dkms_source_dir}/dkms.conf.in > %{buildroot}${dkms_source_dir}/dkms.conf
rm -f %{buildroot}${dkms_source_dir}/dkms.conf.in

%pre dkms

%post dkms
if [ -f /usr/libexec/dkms/common.postinst ] && [ -x /usr/libexec/dkms/common.postinst ]
then
    postinst=/usr/libexec/dkms/common.postinst
elif [ -f /usr/lib/dkms/common.postinst ] && [ -x /usr/lib/dkms/common.postinst ]
then
    postinst=/usr/lib/dkms/common.postinst
else
    echo "ERROR: did not find DKMS common.postinst"
    exit 1
fi
${postinst} %{name} %{version}-%{release}
install -D %{dkms_source_tree}/%{name}-%{version}-%{release}/scripts/rxe_init.sh -m0777 /usr/bin/rxe_init.sh

%preun dkms
#
# `dkms remove` may return an error but that should stop the package from
# being removed.   The " || true" ensures this command line always returns
# success.   One reason `dkms remove` may fail is if someone (an admin)
# already manually removed this dkms package.  But there are some other
# "soft errors" (supposedly) that should not prevent the dkms package
# from being removed.
#
/usr/sbin/dkms remove -m %{name} -v %{version}-%{release} --all --rpm_safe_upgrade || true

%files devel
%{prefix}/src/rxe/*/Module.symvers

%files dkms -f dkms-files

%changelog
