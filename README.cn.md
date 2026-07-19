# fio — 自包含的多平台静态构建

[axboe/fio](https://github.com/axboe/fio) (Jens Axboe 的灵活 I/O 测试工具)
的[vendored](upstream/fio/) 拷贝,加上一个原生的按操作系统封装的层,
产生 **静态链接、自包含** 的二进制文件。目标机器上无需安装 libaio /
zlib / libpthread —— 下载、解压、运行即可。

这是一个 **分发仓库** (fio 源码 + 构建/打包脚本 + CI),与其他
ljh-sh 项目互相独立。x-cmd 的安装模块会另行处理。

## 二进制

每个发布归档的 `bin/` 目录下:

| 二进制    | 用途                                                  |
|----------|---------------------------------------------------------|
| `fio`    | CLI —— 灵活 I/O 测试工具;列出任务,运行 profile         |

(`genfio`、`fio-genzipf`、`fio-verify-state`、`fio-dedupe`、`stest` 等
—— 上游的回归测试辅助二进制 —— **不会** 一起发布;它们在
`upstream/fio/t/`,只在源码树里 `make` 才能用到。)

手册页 `fio(1)` 一同发布,放在 `man/man1/` 下。

## 安装

最快的跨平台一行安装用 x-cmd:

```bash
x eget ljh-sh/fio       # ~1.5 MiB,零依赖,多架构静态构建
```

这会把 `fio` 安装到 `~/.local/bin/fio`。每个发布归档里都自带
`README.md` 描述手动安装的步骤。

不用 x-cmd 的话,从
[Releases 页面](https://github.com/ljh-sh/fio/releases) 抓你平台对应的
归档,`tar xzf` (Windows 上 unzip),把 `bin/fio` 拷到 `$PATH` 里即可。

## 平台矩阵

每次发布通过 GitHub Actions 在原生 runner 上构建 **6 个目标**
(musl 静态 Linux 是在 Alpine 3.20 docker 里跑):

| 目标                     | runner                          | 链接方式                | 归档       |
|--------------------------|---------------------------------|-------------------------|------------|
| `x86_64-linux-musl`      | `ubuntu-latest` + Alpine 3.20   | 完全静态 musl           | `.tar.gz`  |
| `aarch64-linux-musl`     | `ubuntu-24.04-arm` + Alpine 3.20 | 完全静态 musl         | `.tar.gz`  |
| `aarch64-macos`          | `macos-14`                      | 静态,系统 libc++        | `.tar.gz`  |
| `x86_64-macos`           | `macos-14` (从 aarch64 交叉编译) | 静态,系统 libc++       | `.tar.gz`  |
| `x86_64-windows`         | `windows-latest` + MSYS2 + mingw64 | 静态 (无 DLL)        | `.zip`     |
| `aarch64-windows`*       | `windows-11-arm` + MSYS2 + mingw64 | 静态 (无 DLL)        | `.zip`     |

\* `aarch64-windows` 是**矩阵里第 6 个目标**,但加了
`continue-on-error: true`,因为 MSYS2 MINGW64 目前不打包
`mingw-w64-aarch64-gcc` (截至 2026-07-15 已确认空缺;`ljh-sh/lhasa`
和 `ljh-sh/gawk` 同样)。等 MSYS2 加上包,把 `continue-on-error`
豁免去掉就能正常构建。

> **Linux 只发 musl。** 每个 Linux 归档都是一个完全静态的二进制,能在
> Alpine、Debian、Ubuntu、RHEL、Fedora、Arch —— 任何 Linux 发行版上跑,
> 系统库零依赖。**故意不** 发独立的 glibc/动态 Linux 变体。

## 自包含性

- **Linux**: `--build-static` → `-static` → `ldd` 报告 *not a dynamic executable*。
- **macOS**: 静态 (引擎零依赖;只链 `/usr/lib/system/*` 和
  `/usr/lib/libSystem.B.dylib`)。
- **Windows**: 通过 MinGW 用 `/MT` 静态 CRT;`.exe` 不带任何 DLL。

## 安装后快速验证

```bash
$ fio --version
fio-3.41

$ fio --ioengine=null --rw=randrw --runtime=1 --time_based --size=1M --minimal
3;fio-3.41;smoke;0;0;17175736;17158577;4289644;1001;...   # → IOPS 非零,runtime ≈ 1001ms
```

## 从源码构建 (vendoring 更新)

本仓库把 `upstream/fio/` 作为 `git subtree` 拷贝自
`axboe/fio.git` tag `fio-3.41` (commit `ed675d3`, 2025-03)。刷新 vendoring:

```sh
git subtree pull --prefix=upstream/fio \
    https://github.com/axboe/fio.git fio-3.41 --squash
```

然后跑 `bash scripts/build.sh && bash scripts/smoke.sh` 本地复现 CI。
要真正的 musl 静态构建:

```sh
docker run --rm --platform linux/amd64 -v "$PWD":/w -w /w alpine:3.20 \
    sh -c 'apk add --no-cache bash >/dev/null \
        && bash /w/scripts/build-alpine.sh && bash /w/scripts/smoke.sh'
```

## CI

两阶段 GitHub Actions:

- `build-and-test.yml` —— 每次 push 到 `main` 和每个 PR 都会触发;
  完整的 5 目标矩阵;上传每个目标的工件供人查看;**不** 发布 GitHub Release。
- `release.yml` —— tag 推送 (`v*`) 和 `workflow_dispatch` 触发;
  同样的 5 目标矩阵 + `softprops/action-gh-release@v2`,带 tarball、
  zip、每个归档的 `.sha256`、以及顶层的 `SHA256SUMS`。

## 许可

合成作品是 **GPL-2.0-only** (上游就是 GPL-2.0-only)。封装层
(`scripts/`、`.github/`、`README.md`、`NOTICE.md`、`SECURITY.md`、
`LICENSE`、`docs/`) 是 MIT。详见 [`NOTICE.md`](NOTICE.md)。

## 项目状态

- **v0.1.0** (2026-07-15) —— 首次发布;5 目标矩阵;基于上游
  `fio-3.41`。发布同时落地的源码级审计见
  [`AUDIT-2026-07-15.md`](AUDIT-2026-07-15.md)。

渲染后的 Pages 站点: <https://fio.ljh.sh>