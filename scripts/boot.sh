#!/usr/bin/env bash

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

usage() {
  cat << EOF 
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v] [-m] [-b] -k kernel -i initrd -r rootfs

Alpinemini vm

Available options:

-h, --help      Print this help and exit
-v, --verbose   Print script debug info
-k, --kernel 	Specify kernel file
-i, --initrd 	Specify initrd file
-m, --memory    Set maximum vm memory
-b, --build 	Build a new disk (and then boot)
EOF
  exit
}

cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
}

setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
  else
    NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
  fi
}

msg() {
  echo >&2 -e "${1-}"
}

die() {
  local msg=$1
  local code=${2-1}
  msg "$msg"
  exit "$code"
}

parse_params() {
  build=0
  rootfs=''
  kernel=''
  initrd=''
  memory=''

  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) set -x ;;
    --no-color) NO_COLOR=1 ;;
    -b | --build) build=1 ;; # build disk
    -k | --kernel) # kernel file
      kernel="${2-}"
      shift
      ;;
    -i | --initrd) # initrd file
      initrd="${2-}"
      shift
      ;;
    -m | --memory) # max memory
      memory="${2-}"
      shift
      ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  args=("$@")

  # check required params and arguments
  [[ -z "${kernel-}" ]] && die "${RED}Missing required parameter:${NOFORMAT} kernel"
  [[ -z "${initrd-}" ]] && die "${RED}Missing required parameter:${NOFORMAT} initrd"

  return 0
}
setup_colors
parse_params "$@"

if ! [ -x "$(command -v qemu-system-x86_64)" ]; then
  echo '${RED}Error:${NOFORMAT} unable to find qemu-system-x86_64, please install it first.' >&2
  exit 1
fi

if ! [ -x "$(command -v qemu-img)" ]; then
  echo '${RED}Error:${NOFORMAT} unable to find qemu-img, please install it first.' >&2
  exit 1
fi


if [[ $build -eq 1 ]]
then
 msg "${CYAN}Building disk... Please wait${NOFORMAT}"
 qemu-img create -f qcow2 vm.qcow2 800M
 qemu-system-x86_64 -m 256M -smp 1 -drive file=packervm/packer.qcow2,if=virtio,readonly=on -drive file=vm.qcow2,if=virtio -enable-kvm -fsdev local,id=rootfs_dev,path=rootfs,security_model=none -device virtio-9p-pci,fsdev=rootfs_dev,mount_tag=rootfs -display none
fi

qemumem=''
if ! [[ $memory -eq "" ]]
 then
   qemumem="-m ${memory}"
fi

qemu-system-x86_64 -net nic,model=virtio,netdev=user.0 -netdev user,id=user.0 -drive file=vm.qcow2,if=virtio -enable-kvm -kernel ${kernel} -initrd ${initrd} ${qemumem}  -append 'root=/dev/vda1 rw quiet modules=ext4 console=ttyS0,9600 console=ttyS0 init=/bin/nimd'
