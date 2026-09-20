# oqs-provider-with-kpqc

`oqs-provider-with-kpqc` is a research-oriented fork of the Open Quantum Safe `oqs-provider` that exposes Korean Post-Quantum Cryptography (KpqC) algorithms through the **OpenSSL 3 provider interface**.

This repository allows KpqC algorithms implemented in [`liboqs-with-KpqC`](https://github.com/17seetwice/liboqs-with-KpqC) to be used with OpenSSL commands, EVP APIs, X.509 certificates, and TLS 1.3 experiments.

Supported KpqC families in this fork:

- **Digital signatures:** AIMer, HAETAE
- **KEMs:** SMAUG/SMAUG-T, NTRU+

> **Research/prototyping only.** This repository is intended for experimentation, interoperability testing, benchmarking, and academic research.

---

## 1. Before you start: what does this repository do?

```text
TLS / X.509 / OpenSSL CLI
          |
          v
      OpenSSL 3.x
          |
          v
oqs-provider-with-kpqc
          |
          v
  liboqs-with-KpqC
          |
          +-- AIMer
          +-- HAETAE
          +-- SMAUG / SMAUG-T
          +-- NTRU+
```

- `liboqs-with-KpqC` provides the cryptographic implementations.
- `oqs-provider-with-kpqc` is the adapter that exposes those algorithms to OpenSSL 3.
- **Install `liboqs-with-KpqC` first.**
- For TLS 1.3 PQ signature testing, use OpenSSL **3.2 or newer**. This guide uses **OpenSSL 3.4.4**.

---

## 2. Verified environment

| Component | Verified configuration |
|---|---|
| OS | Ubuntu 24.04 LTS |
| Architecture | x86_64 |
| WSL | WSL2 supported for local development |
| OpenSSL | 3.4.4 |
| liboqs | `liboqs-with-KpqC` |
| Build tools | GCC, CMake, Ninja |
| OpenSSL install prefix | `/opt/openssl-3.4.4` |
| KpqC liboqs install prefix | `/opt/liboqs-kpqc` |

The paths under `/opt` are intentionally used so that the Ubuntu system OpenSSL does **not** need to be removed or overwritten.

---

## 3. Quick start — Ubuntu 24.04

### Step 1. Install build tools

```bash
sudo apt update
sudo apt install -y \
    git \
    wget \
    build-essential \
    cmake \
    ninja-build \
    perl \
    python3 \
    pkg-config \
    ca-certificates
```

### Step 2. Install OpenSSL 3.4.4 side-by-side

Do **not** replace `/usr/bin/openssl` or Ubuntu's system `libssl`.

```bash
mkdir -p ~/kpqc-build
cd ~/kpqc-build

wget https://github.com/openssl/openssl/archive/refs/tags/openssl-3.4.4.tar.gz
tar -xzf openssl-3.4.4.tar.gz
cd openssl-openssl-3.4.4
```

```bash
./Configure \
  --prefix=/opt/openssl-3.4.4 \
  --openssldir=/opt/openssl-3.4.4/ssl \
  --libdir=lib \
  shared

make -j$(nproc)
make test
sudo make install
```

Use the new OpenSSL only in the current shell:

```bash
export PATH=/opt/openssl-3.4.4/bin:$PATH
export LD_LIBRARY_PATH=/opt/openssl-3.4.4/lib:$LD_LIBRARY_PATH
```

Verify:

```bash
openssl version
```

Expected:

```text
OpenSSL 3.4.4 ...
```

If OpenSSL reports an error such as `OPENSSL_3.4.0 not found`, run:

```bash
ldd /opt/openssl-3.4.4/bin/openssl
```

`libssl.so.3` and `libcrypto.so.3` should resolve to `/opt/openssl-3.4.4/lib/`.

### Step 3. Build and install liboqs-with-KpqC

```bash
cd ~/kpqc-build

git clone https://github.com/17seetwice/liboqs-with-KpqC.git
cd liboqs-with-KpqC

cmake -S . -B build \
  -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=ON \
  -DCMAKE_INSTALL_PREFIX=/opt/liboqs-kpqc

cmake --build build -j$(nproc)
sudo cmake --install build
```

Verify:

```bash
find /opt/liboqs-kpqc -name "liboqsConfig.cmake"
```

Typical result:

```text
/opt/liboqs-kpqc/lib/cmake/liboqs/liboqsConfig.cmake
```

### Step 4. Build oqs-provider-with-kpqc

```bash
cd ~/kpqc-build

git clone https://github.com/17seetwice/oqs-provider-with-kpqc.git
cd oqs-provider-with-kpqc
```

```bash
export OPENSSL_ROOT_DIR=/opt/openssl-3.4.4
export PATH=/opt/openssl-3.4.4/bin:$PATH
export LD_LIBRARY_PATH=/opt/openssl-3.4.4/lib:/opt/liboqs-kpqc/lib:$LD_LIBRARY_PATH
```

```bash
cmake -S . -B _build \
  -DOPENSSL_ROOT_DIR=/opt/openssl-3.4.4 \
  -Dliboqs_DIR=/opt/liboqs-kpqc/lib/cmake/liboqs \
  -DCMAKE_BUILD_TYPE=Release

cmake --build _build -j$(nproc)
ctest --test-dir _build --output-on-failure
```

A successful build should finish with:

```text
100% tests passed, 0 tests failed
```

---

## 4. Activate oqsprovider in your shell

Building the provider is not enough: OpenSSL must know **where the provider module is** and **which OpenSSL configuration file activates it**.

From the repository root:

```bash
export PATH=/opt/openssl-3.4.4/bin:$PATH
export LD_LIBRARY_PATH=/opt/openssl-3.4.4/lib:/opt/liboqs-kpqc/lib:$LD_LIBRARY_PATH
export OPENSSL_MODULES=$PWD/_build/lib
export OPENSSL_CONF=$PWD/scripts/openssl-ca.cnf
```

Check active providers:

```bash
openssl list -providers
```

Expected output should include both:

```text
default
oqsprovider
```

---

## 5. Verify the KpqC algorithms

### Digital signatures

```bash
openssl list -signature-algorithms | grep -Ei "aimer|haetae"
```

Expected names include:

```text
haetae2
haetae3
haetae5
aimer128f
aimer128s
aimer192f
aimer192s
aimer256f
aimer256s
```

### KEMs

```bash
openssl list -kem-algorithms | grep -Ei "smaug|ntruplus"
```

Expected names include:

```text
smaug1
smaug3
smaug5
ntruplus_kem576
ntruplus_kem768
ntruplus_kem864
ntruplus_kem1152
```

### TLS 1.3 signature algorithms

OpenSSL 3.4+ can list active TLS signature algorithms:

```bash
openssl list -tls-signature-algorithms | tr ':' '\n' | grep -Ei "aimer|haetae"
```

---

## 6. Minimal TLS 1.3 AIMer smoke test

### Generate a key

```bash
mkdir -p ~/aimer-test
cd ~/aimer-test

openssl genpkey \
  -algorithm aimer128s \
  -out aimer128s.key
```

### Create a self-signed certificate

```bash
openssl req \
  -new \
  -x509 \
  -key aimer128s.key \
  -out aimer128s.crt \
  -subj "/CN=localhost" \
  -days 1
```

Check it:

```bash
openssl x509 \
  -in aimer128s.crt \
  -text \
  -noout | grep -E "Signature Algorithm|Public Key Algorithm"
```

### Terminal 1 — server

```bash
openssl s_server \
  -cert aimer128s.crt \
  -key aimer128s.key \
  -accept 4433 \
  -tls1_3 \
  -sigalgs aimer128s \
  -www
```

### Terminal 2 — client

Set the same OpenSSL environment variables in the second shell, then run:

```bash
openssl s_client \
  -connect 127.0.0.1:4433 \
  -tls1_3 \
  -sigalgs aimer128s \
  -servername localhost
```

A self-signed-certificate warning is expected for this local test.

---

## 7. Troubleshooting

### `openssl list -providers` shows only `default`

Check:

```bash
echo "$OPENSSL_MODULES"
echo "$OPENSSL_CONF"
```

For a local build, they should point to:

```text
.../oqs-provider-with-kpqc/_build/lib
.../oqs-provider-with-kpqc/scripts/openssl-ca.cnf
```

### `OPENSSL_3.4.0 not found`

Your OpenSSL 3.4.4 executable is probably loading Ubuntu's older system `libssl.so.3`.

```bash
export LD_LIBRARY_PATH=/opt/openssl-3.4.4/lib:/opt/liboqs-kpqc/lib:$LD_LIBRARY_PATH
ldd /opt/openssl-3.4.4/bin/openssl
```

### Provider builds but KpqC algorithms do not appear

Confirm that this fork of liboqs is being used:

```bash
find /opt/liboqs-kpqc -name "liboqsConfig.cmake"
```

Then configure again with:

```text
-Dliboqs_DIR=/opt/liboqs-kpqc/lib/cmake/liboqs
```

---

## 8. KpqC algorithms and learning resources

| Algorithm | Type | Core idea | Official resource |
|---|---|---|---|
| **AIMer** | Signature | Symmetric primitive + MPC-in-the-Head | https://aimer-signature.org/ |
| **HAETAE** | Signature | Module-LWE/SIS + Fiat-Shamir with Aborts | https://kpqc.cryptolab.co.kr/haetae |
| **SMAUG / SMAUG-T** | KEM | Module-LWE + Module-LWR + FO transform | https://kpqc.cryptolab.co.kr/smaug-t |
| **NTRU+** | KEM | NTRU-based lattice KEM | https://www.ntruplus.org/ |

Official KpqC final algorithm documents:
- https://www.kpqc.or.kr/contents/03_exhibit/sub_03.html

### AIMer

- Technical document: https://aimer-signature.org/docs/AIMer-KpqC-Document.pdf
- Paper/ePrint: https://eprint.iacr.org/2022/1387
- Reference implementation: https://github.com/samsungsds-research-papers/AIMer

### HAETAE

- Official site: https://kpqc.cryptolab.co.kr/haetae
- KpqC document: https://www.kpqc.or.kr/images/pdf2/HAETAE.pdf
- Paper: https://doi.org/10.46586/tches.v2024.i3.25-75
- ePrint: https://eprint.iacr.org/2023/624
- Reference implementation: https://github.com/CryptoLabInc/HAETAE

### SMAUG / SMAUG-T

- Official site and newest specifications: https://kpqc.cryptolab.co.kr/smaug-t
- KpqC document: https://www.kpqc.or.kr/images/pdf/Smaug.pdf
- Updated paper: https://doi.org/10.1109/ACCESS.2024.3511346
- Foundational SAC 2023 paper: https://doi.org/10.1007/978-3-031-53368-6_7
- Reference implementation: https://github.com/CryptoLabInc/SMAUG-T

### NTRU+

- Official site: https://www.ntruplus.org/
- KpqC document: https://kpqc.or.kr/images/pdf2/NTRU%2B.pdf
- IEEE TIFS paper: https://doi.org/10.1109/TIFS.2023.3299172
- ePrint: https://eprint.iacr.org/2022/1664
- Reference implementation: https://github.com/ntruplus/ntruplus

---

## 9. Related publication

For broader background and comparison between NIST PQC and KpqC algorithms:

> 김명준, 서유진, 김영식, **“NIST PQC와 KpqC 알고리즘 비교 분석”**,  
> 2025년도 한국통신학회 하계종합학술발표회 논문집, pp. 1630–1631, June 2025.

- DBpia: https://www.dbpia.co.kr/journal/articleDetail?nodeId=NODE12361391

---

## 10. Upstream documentation

- Upstream oqs-provider: https://github.com/open-quantum-safe/oqs-provider
- Upstream liboqs: https://github.com/open-quantum-safe/liboqs
- Open Quantum Safe: https://openquantumsafe.org/

KpqC-specific behavior and installation instructions in this repository take precedence where they differ from upstream.
