FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    qemu-system-x86 \
    qemu-kvm \
    qemu-utils \
    novnc \
    websockify \
    wget \
    curl \
    net-tools \
    unzip \
    python3 \
    aria2 \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /data /iso /novnc

RUN wget -q https://github.com/novnc/noVNC/archive/refs/heads/master.zip -O /tmp/novnc.zip && \
    unzip /tmp/novnc.zip -d /tmp && \
    mv /tmp/noVNC-master/* /novnc && \
    rm -rf /tmp/novnc.zip /tmp/noVNC-master && \
    ln -sf /novnc/vnc.html /novnc/index.html

RUN cat > /start.sh << 'EOF'
#!/bin/bash
set -e

# KVM check
if [ -e /dev/kvm ]; then
  echo "✅ KVM available"
  KVM_ARG="-enable-kvm"
  CPU_ARG="host"
  MEMORY="3G"
  SMP_CORES=2
else
  echo "⚠️ KVM not available - slow mode"
  KVM_ARG=""
  CPU_ARG="qemu64"
  MEMORY="2G"
  SMP_CORES=1
fi

# ISO download
ISO_FILE="/iso/os.iso"
if [ ! -f "$ISO_FILE" ]; then
  echo "📥 Downloading Tiny10 ISO..."
  aria2c -x 8 -s 8 --dir=/iso --out=os.iso \
    "https://archive.org/download/tiny-10-23-h2/tiny10%20x64%2023h2.iso"
  echo "✅ ISO downloaded"
fi

# Disk create
if [ ! -f "/data/disk.qcow2" ]; then
  echo "💽 Creating 40GB virtual disk..."
  qemu-img create -f qcow2 /data/disk.qcow2 40G
fi

# Boot order
DISK_SIZE=$(stat -c%s /data/disk.qcow2 2>/dev/null || echo 0)
if [ "$DISK_SIZE" -lt 10485760 ]; then
  echo "🚀 First boot - booting from ISO"
  BOOT_ORDER="-boot order=d,menu=on"
else
  echo "🔄 Booting from disk"
  BOOT_ORDER="-boot order=c,menu=on"
fi

echo "⚙️ Starting VM with ${SMP_CORES} cores and ${MEMORY} RAM..."

# Start QEMU
qemu-system-x86_64 \
  $KVM_ARG \
  -machine q35 \
  -cpu $CPU_ARG \
  -m $MEMORY \
  -smp $SMP_CORES \
  -vga std \
  -usb -device usb-tablet \
  $BOOT_ORDER \
  -drive file=/data/disk.qcow2,format=qcow2,if=virtio \
  -drive file=$ISO_FILE,media=cdrom,readonly=on \
  -netdev user,id=net0,hostfwd=tcp::3389-:3389 \
  -device e1000,netdev=net0 \
  -display vnc=:0 \
  -name "Windows10_VM" &

QEMU_PID=$!
echo "✅ QEMU started (PID: $QEMU_PID)"

# Wait for VNC to be ready
echo "⏳ Waiting for VNC..."
sleep 8

# Start noVNC
websockify --web /novnc 6080 localhost:5900 &
echo "✅ noVNC started"

echo ""
echo "===================================="
echo "🌐 noVNC:  http://localhost:6080"
echo "🖥️  RDP:    localhost:3389"
echo "⚠️  First install = 20-30 minutes"
echo "===================================="

wait $QEMU_PID
EOF

RUN chmod +x /start.sh

VOLUME ["/data", "/iso"]
EXPOSE 6080 3389
CMD ["/start.sh"]
