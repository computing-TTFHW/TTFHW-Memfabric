<div align="center">
  <img src=doc/source/memfabric_icon.png style="width: 50%" />
  <h2 align="center">DRAM&HBM hybrid pooling, memory semantic interface, high-performance cross-machine memory direct access</h2>
</div>

## 环境准备

| 平台 | 镜像地址 |
|------|----------|
| aarch64/arm64 | `swr.cn-north-4.myhuaweicloud.com/memfabric-hybrid/memfabric-hybrid_arm:v20` |
| x86_64 | `swr.cn-north-4.myhuaweicloud.com/memfabric-hybrid/memfabric-hybrid_x86:v20` |

```bash
docker pull swr.cn-north-4.myhuaweicloud.com/memfabric-hybrid/memfabric-hybrid_arm:v20   # aarch64
docker pull swr.cn-north-4.myhuaweicloud.com/memfabric-hybrid/memfabric-hybrid_x86:v20  # x86_64
```

## 编译软件包

1. 下载代码并初始化子模块：
```bash
git clone https://gitcode.com/Ascend/memfabric_hybrid
cd memfabric_hybrid
git submodule update --recursive --init
```

2. 编译（生成run包）：
```bash
bash script/build_and_pack_run.sh --build_mode RELEASE --build_python ON --xpu_type NPU --build_test OFF --build_hcom OFF
```

编译成功后，run包生成在 `output/` 目录下。

**编译参数说明**：

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--build_mode` | 编译类型：RELEASE / DEBUG / ASAN | RELEASE |
| `--build_python` | 是否编译python的whl包：ON / OFF | ON |
| `--xpu_type` | 指定异构设备：NPU(昇腾) / GPU(CUDA) / NONE(无卡) | NPU |
| `--build_test` | 是否编译打包测试工具和样例代码：ON / OFF | OFF |
| `--build_hcom` | 是否编译hcom：ON / OFF | OFF |
| `--build_hcom_rdma` | hcom是否启用rdma：ON / OFF | ON |
| `--build_hcom_ub` | hcom是否启用ub(urma)：ON / OFF | OFF |
| `--build_etcd_backend` | 是否编译etcd backend so：ON / OFF | OFF |
| `--build_tool` | 构建工具：cmake / bazel | cmake |

### 安装软件包

run包的默认安装根路径为 `/usr/local/`：

```bash
bash memfabric_hybrid-1.1.0_linux_aarch64.run
source /usr/local/memfabric_hybrid/set_env.sh
```

自定义安装路径：
```bash
bash memfabric_hybrid-1.1.0_linux_aarch64.run --install-path=${your_path}
```

### 安装Python包(whl)

```bash
# 方式1: 使用run包中的whl
pip install /usr/local/memfabric_hybrid/latest/aarch64-linux/wheel/memfabric_hybrid-1.1.0-cp311-cp311-linux_aarch64.whl

# 方式2: 从PyPI在线安装
pip install memfabric_hybrid==1.1.0
```

whl包安装完成后，需要设置LD_LIBRARY_PATH环境变量：
```bash
export LD_LIBRARY_PATH=/usr/local/lib/python3.11/site-packages/memfabric_hybrid/lib/:$LD_LIBRARY_PATH
```

## 单元测试（UT）

项目使用googletest + mockcpp作为测试框架。测试用例位于 `test/ut/testcase/` 目录。

**运行UT**：

使用 `script/run_ut.sh` 脚本编译并运行所有单元测试：

```bash
# 完整模式：全量构建 + 代码覆盖率报告
bash script/run_ut.sh

# 快速模式：增量构建，跳过覆盖率报告
bash script/run_ut.sh --fast

# 按名称过滤测试用例
bash script/run_ut.sh SmemBmTest
bash script/run_ut.sh --fast HybmMemSegment
```

**UT模式对比**：

| 特性 | 默认模式 | `--fast` 模式 |
|------|----------|---------------|
| 构建目录清理 | 全量清理 | 跳过（增量） |
| cmake重新配置 | 每次 | 仅首次或指纹不匹配时 |
| 覆盖率报告 | 生成 | 跳过 |
| 适用场景 | CI / pre-commit | 本地开发快速迭代 |

**UT编译参数**：

UT使用CMake的ASAN和coverage构建配置：
- `CMAKE_BUILD_TYPE=ASAN`（地址消毒检测）
- `BUILD_UT=ON`（启用单元测试编译）
- `BUILD_OPEN_ABI=ON`（使用C++11 ABI）

**代码覆盖率**：

运行 `bash script/run_ut.sh`（非fast模式）会自动生成覆盖率报告：

```bash
bash script/run_ut.sh
# 覆盖率报告生成在 output/coverage/result/ 目录
```

要求覆盖率标准：行覆盖率 >= 70%，分支覆盖率 >= 40%
