#!/bin/sh

ethdevs=""
if [[ $# -lt 1 ]] ; then
	ethdevs="hsn0"
else
	ethdevs="$1"
	shift
	while [ $# -gt 0 ]; do
		ethdevs="$ethdevs $1"
		shift
	done
fi

echo "Configuring Soft RoCE for $ethdevs"

# Check if the cxi_ss1 is running
if [[ ! -d /sys/class/cxi ]] ; then
	echo "RXE requires CXI ethernet to be configured in order to work."
	echo "Start the Cassini Driver, configure ethernet,"
	echo "(including algorithmic MAC addressing), then re-run rxe_init.sh"
	exit 1
fi

# Check if the ethdev(s) exist 
badeths=""
for ethdev in $ethdevs; do
	dev=$(find /sys/devices/ -name "$ethdev");
	if [[ $dev == "" ]] ; then 
		if [ "$badeths" == "" ] ; then
			badeths=$ethdev
		else
			badeths="$badeths $ethdev"
		fi
	fi
done

if [[ "$badeths" != "" ]] ; then
	echo "Devices [$badeths] are not configured"
	echo "RXE requires ethernet to be configured in order to work."
	echo "Configure ethernet (including algorithmic MAC addressing), then re-run rxe_init.sh"
	exit 1
fi

# Check if the settings for the ethdev are correct
if [[ $(cat /sys/module/cxi_eth/parameters/large_pkts_buf_count) -ne 10000 ]] ; then
	echo "RXE requires cxi_eth to be configured with large_pkts_buf_count=10000"
	echo "Please modify system configuration and re-run rxe_init.sh"
	exit 1;
fi

# Check if rxe is up
rxeup=0
for ethdev in $ethdevs; do
	rxeup=$((rxeup + $(rdma link show | grep -c $ethdev)))
done
if [ $rxeup -gt 0 ] ; then
	modprobe -r rdma_rxe
	if [[ $? -ne 0 ]] ; then 
		echo "RXE device(s) in use, please shut down whatever app is using it prior to running rxe_init.sh"
		exit 1
	fi
fi

# Adjust system settings
sysctl -w net.core.netdev_budget=5000
sysctl -w net.core.netdev_budget_usecs=10000
sysctl -w net.core.netdev_max_backlog=900000
sysctl -w net.core.rmem_default=134217728
sysctl -w net.core.rmem_max=134217728
sysctl -w net.ipv4.udp_rmem_min=131072
sysctl -w net.ipv4.udp_wmem_min=131072
sysctl -w net.ipv4.udp_mem="8388608 33554432 67108864"

for ethdev in $ethdevs; do
	macaddr=$(cat /sys/class/net/${ethdev}/address)
	vendorid=$(echo $macaddr | cut -d":" -f 1,2,3)
	if [[ "$vendorid" == "00:40:a6" ]] ; then
		echo "Please assign algorithmic MAC addresses prior to rxe_init.sh"
		exit 1
	fi
	linkchange=0
	setmtu=0
	mtu=$(ip addr show dev $ethdev | grep mtu | sed -e "s/  */ /" | cut -d" " -f6)
	if [[ $mtu != "9000" ]] ; then
		setmtu=1
		linkchange=$(( $linkchange + 1))
	fi
	setrx=0
	if [[ $(ls /sys/class/net/${ethdev}/queues/ | grep -c rx) != "16" ]] ; then
		setrx=1
		linkchange=$(( $linkchange + 1))
	fi
	settx=0
	if [[ $(ls /sys/class/net/${ethdev}/queues/ | grep -c tx) != "16" ]] ; then
		settx=1
		linkchange=$(( $linkchange + 1))
	fi
	setroceopt=0
	if [[ $(ethtool --show-priv-flags $ethdev | grep roce-opt | sed -e"s/  *//g" | cut -d":" -f2) != "on" ]] ; then
		setroceopt=1
		linkchange=$(( $linkchange + 1))
	fi
	# Check if the link is up
	linkup=0
	linkstate=$(cat /sys/class/net/${ethdev}/operstate)
	if [[ $linkstate == "up" ]] ; then
		linkup=1
	fi

	# Modify any settings that require it
	if [[ $linkchange -gt 0 ]] ; then
		if [[ $linkup -ne 0 ]] ; then
			linkup=0
			ip link set $ethdev down
			if [[ $? -ne 0 ]] ; then
				echo "Unable to bring eth link down to change settings"
				exit 1
			fi
		fi
	fi

	if [[ $setmtu -eq 1 ]] ; then
		ip link set dev $ethdev mtu 9000
		if [[ $? -ne 0 ]] ; then
			echo "Failed to set $ethdev mtu to 9000"
			exit 1
		fi
	fi
	if [[ $(( $setrx + $settx )) -gt 0 ]] ; then
		ethtool -L $ethdev rx 16 tx 16
		if [[ $? -ne 0 ]] ; then
			echo "Failed to set $ethdev rx/tx queues to 16/16" 
			exit 1
		fi
	fi
	if [[ $setroceopt -eq 1 ]] ; then
		ethtool --set-priv-flags $ethdev roce-opt on
		if [[ $? -ne 0 ]] ; then
			echo "Failed to enable $ethdev RoCE optimizations"
			exit 1
		fi
	fi

	# Bring up the link (if needed)
	if [[ $linkup -ne 1 ]] ; then
		ip link set $ethdev up
		if [[ $? -ne 0 ]] ; then
			echo "Failed to bring $ethdev link up"
			exit 1
		fi
	fi


	# Change the tx queue discipline
	NUM_TX=$(ethtool -l $ethdev | grep TX | tail -n 1 | sed -e's/\s\s*//g' | cut -d':' -f 2)
	for ((i=0; i<$NUM_TX; i++));  do echo 8388608 > /sys/class/net/$ethdev/queues/tx-$i/byte_queue_limits/limit_min; done

	# Create the rxe device
	# Default to using rxedev is rxe# where # is the ethdev number
	rxedev=$(echo "$ethdev" | sed -e "s/[a-z_]*/rxe/")
	rdma link add $rxedev type rxe netdev $ethdev
	if [[ $? -ne 0 ]] ; then
		echo "Unable to create $rxedev on $ethdev"
		exit 1
	fi
done

echo 8 >/sys/module/rdma_rxe/parameters/max_pkt_per_ack
echo 16 >/sys/module/rdma_rxe/parameters/max_unacked_psns
echo 64 >/sys/module/rdma_rxe/parameters/inflight_skbs_per_qp_low
echo 256 >/sys/module/rdma_rxe/parameters/inflight_skbs_per_qp_high
