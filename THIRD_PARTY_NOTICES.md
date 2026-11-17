# Third-party notices

## Slamtec / rplidar_sdk

The wire protocol implemented in `td/src/s2e_driver.py` and `scripts/s2e.ps1`
(request framing, response descriptors, `GET_LIDAR_CONF` fields, HQ measurement frame
layout, dense-capsule and standard-scan node layouts, and the zero-padded CRC32)
follows Slamtec's public *RPLIDAR Interface Protocol and Application Notes* and the
reference implementation in https://github.com/Slamtec/rplidar_sdk

No Slamtec source code is included or copied; the implementations here were written
from the protocol description and verified against an RPLIDAR S2E (model 0x71,
firmware 1.02, hardware 18) over its Ethernet/UDP interface.

```
BSD 2-Clause License

Copyright (c) 2009 - 2014 RoboPeak Team
Copyright (c) 2014 - 2019 Shanghai Slamtec Co., Ltd.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## Drivers

This package bundles and redistributes no drivers. The RPLIDAR S2E is an Ethernet
device and needs none: it is reached over UDP through the operating system's own
network stack. The installer's only system change is adding a secondary IPv4 address
to a network adapter, which `odinstaluj.bat` removes again.
