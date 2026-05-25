# Radix Sort 算法性能比较与分析报告

生成日期：2026-05-12  
平台：NVIDIA Tegra Thor  
比较对象：

1. `jaesung-cs/vulkan_radix_sort`
2. `MircoWerner/VkRadixSort` multi variant
3. Embree `v4.0.0-ploc` `sort.h` radix sort 的 CUDA port

## 1. 结论摘要

在当前 NVIDIA Tegra Thor 上，针对 `N = 1,048,576` 个 32-bit key 的同规模排序实测结果显示：

| 排名 | 方法 | keys-only 时间 | keys-only 吞吐 | key-value 时间 | key-value 吞吐 |
|---:|---|---:|---:|---:|---:|
| 1 | jaesung-cs/vulkan_radix_sort | 0.714592 ms | 1.467 GItems/s | 0.812640 ms | 1.290 GItems/s |
| 2 | Embree sort CUDA port | 1.066560 ms | 0.983 GItems/s | 1.360991 ms | 0.770 GItems/s |
| 3 | MircoWerner/VkRadixSort multi | p50 ≈ 2.250 ms | ≈ 0.466 GItems/s | 未测 | 未测 |

核心结论：

- `jaesung-cs/vulkan_radix_sort` 是本轮实测最快方法。
- Embree CUDA port 稳定排第二，但它不是原始 Embree SYCL/Level Zero 路径，而是按 Embree `sort.h` large path 思路移植到 CUDA 的版本。
- `MircoWerner/VkRadixSort` multi 在本机上 keys-only 明显更慢，并且出现很长的运行时间尾部。
- key-value 场景下，`jaesung-cs/vulkan_radix_sort` 约为 Embree CUDA port 的 `1.67×`。

## 2. 实验配置

### 2.1 硬件与运行环境

| 项目 | 值 |
|---|---|
| GPU | NVIDIA Tegra NVIDIA Thor |
| NVIDIA Driver | 580.00 |
| CUDA | 13.0 / nvcc 13.0.48 |
| Vulkan Device API | 1.4.315 |
| OS | Linux aarch64 |

### 2.2 输入规模

本轮主比较统一使用：

```text
N = 1,048,576 = 2^20
```

排序数据类型：

- keys-only：`uint32_t key`
- key-value：`uint32_t key + uint32_t value`

正确性基准：

- keys-only：与 CPU `std::sort` 结果逐元素比较。
- key-value：与 CPU stable sort by key 的结果逐元素比较。

## 3. 三种方法的算法结构

## 3.1 jaesung-cs/vulkan_radix_sort

该方法采用 Vulkan compute shader 实现 4-pass 8-bit radix sort。每一轮处理 8 bit，因此 32-bit key 需要 4 轮。

每轮主要由三阶段组成：

```text
upsweep → spine → downsweep
```

### 结构特点

1. **upsweep**
   - 按 partition/workgroup 统计局部 256-bin histogram。
   - 每个 pass 只统计当前 8-bit radix digit。

2. **spine**
   - 对所有 partition 的 histogram 做全局 prefix-sum。
   - 将每个 bin、每个 partition 的全局 scatter 起点预先算好。

3. **downsweep**
   - 根据 spine 结果进行 scatter。
   - workgroup 内部使用局部 rank/prefix 技术保证元素被放到正确位置。

### 性能优势来源

`jaesung-cs/vulkan_radix_sort` 的主要优势是它把 histogram prefix 的全局工作集中到 `spine` 阶段完成，避免每个 scatter workgroup 重复扫描全局 histogram。

这使其具备以下优点：

- 全局 prefix 工作只做一次。
- scatter 阶段可以直接使用预计算 offset。
- 减少重复 global memory 读取。
- pipeline 结构清晰，适合 GPU 并行化。
- Vulkan timestamp 直接测 GPU 排序段，计时边界较干净。

## 3.2 MircoWerner/VkRadixSort multi

`VkRadixSort` multi variant 也属于多 workgroup radix sort，但其结构与 jaesung 的三阶段 pipeline 不同。

### 结构特点

- 每轮 radix pass 中包含 histogram 与 scatter 逻辑。
- 多个 workgroup 并行处理数据。
- key-only 场景已运行；本轮未获得同口径 key-value 数据。

### 性能劣势来源

本轮代码与实测分析显示，`VkRadixSort` multi 的主要问题不是单个 shader 指令慢，而是算法结构存在较大的重复工作：

- 每个 workgroup 在计算 scatter offset 时会重复读取或累加较多 histogram 信息。
- 对 `N = 2^20` 这类规模，重复 histogram offset 计算会显著放大全局内存访问量。
- example 程序的计时口径是 CPU wall-clock，包含提交、等待等 host 侧开销。
- 本轮 10 次运行中出现明显长尾，最大值达到 `160.228 ms`。

因此，`VkRadixSort` multi 的实测结果既反映算法结构的冗余，也受到测量口径和运行时波动影响。

## 3.3 Embree sort CUDA port

Embree 原始路径来自：

```text
Embree v4.0.0-ploc/kernels/rthwif/builder/gpu/sort.h
```

原始 Embree GPU sort 是 SYCL/Level Zero/Intel GPU oriented 的实现，包含 Intel-specific subgroup/builtin 路径，不能在当前 NVIDIA Tegra Thor 上直接公平运行。因此本轮实现的是 CUDA port，并在 benchmark 中明确标记为：

```text
Embree v4.0.0-ploc radix_sort_Nx8Bit CUDA port (separate prefix kernel)
```

### CUDA port 结构

当前 port 保留 Embree large radix sort 的核心思路：

- 8-bit radix。
- 256 bins。
- 512 threads/block。
- 多 DSS/workgroup 分块。
- 每个 pass 先统计 histogram，再计算 offset，再 scatter。
- keys-only 与 key-value 都通过 CPU reference correctness check。

当前 CUDA port 每轮大致为：

```text
binning kernel → build-offsets kernel → scatter kernel
```

### 与原始 Embree 的差异

该实现不是原始 Embree SYCL kernel 的逐行翻译，也不是原始 Intel GPU 后端性能。主要差异：

- 原始 Embree 面向 Intel SYCL/Level Zero；本实现面向 NVIDIA CUDA。
- 当前 port 使用单独的 prefix/offset kernel，因此版本字符串标注了 `separate prefix kernel`。
- 原始 Embree PLOC 场景常处理 Morton code / BVH 构建相关数据；本轮为了与 Vulkan sort 公平比较，使用 32-bit key 和 32-bit key-value。

因此它适合作为“Embree radix sort 思路在 NVIDIA Thor 上的 CUDA 移植版本”参与比较，而不应被表述为原始 Embree 官方 GPU 后端性能。

## 4. 实测结果

## 4.1 jaesung-cs/vulkan_radix_sort

命令形态：

```bash
benchmark_repos/vulkan_radix_sort/build_embree_cuda/bench \
  vulkan \
  benchmark_repos/vulkan_radix_sort/build_embree_cuda/compare_round_vulkan.csv \
  1048576
```

CSV 结果：

```text
vulkan,1048576,keys,0.714592,0.781224,1.467377,1.342222
vulkan,1048576,kv,0.812640,0.945454,1.290333,1.109071
```

含义：

| sort | GPU time | CPU wall time | GPU throughput | CPU throughput |
|---|---:|---:|---:|---:|
| keys | 0.714592 ms | 0.781224 ms | 1.467377 GItems/s | 1.342222 GItems/s |
| kv | 0.812640 ms | 0.945454 ms | 1.290333 GItems/s | 1.109071 GItems/s |

## 4.2 Embree CUDA port

命令形态：

```bash
benchmark_repos/vulkan_radix_sort/build_embree_cuda/bench \
  embree-cuda \
  benchmark_repos/vulkan_radix_sort/build_embree_cuda/compare_round_embree_cuda.csv \
  1048576
```

CSV 结果：

```text
embree-cuda,1048576,keys,1.066560,1.176933,0.983138,0.890939
embree-cuda,1048576,kv,1.360991,1.391450,0.770450,0.753585
```

含义：

| sort | GPU time | CPU wall time | GPU throughput | CPU throughput |
|---|---:|---:|---:|---:|
| keys | 1.066560 ms | 1.176933 ms | 0.983138 GItems/s | 0.890939 GItems/s |
| kv | 1.360991 ms | 1.391450 ms | 0.770450 GItems/s | 0.753585 GItems/s |

## 4.3 MircoWerner/VkRadixSort multi

本轮 repeated runs：

```text
1.967, 2.342, 2.159, 4.012, 0.956, 8.534, 160.228, 9.487, 1.549, 1.334 ms
```

统计：

| 指标 | 时间 |
|---|---:|
| min | 0.956 ms |
| p50 | ≈ 2.250 ms |
| max | 160.228 ms |
| mean | 19.257 ms |

说明：

- 当前结果是 keys-only。
- 计时来自 example 程序输出的 CPU wall-clock，非统一 `bench` harness 的 GPU timestamp median。
- 该方法出现明显长尾，因此 mean 被极端值严重拉高。
- 用 p50 与其他方法比较更合理，但仍不是完全同口径。

## 5. 相对性能比较

## 5.1 keys-only

以 GPU/kernel 排序段时间比较：

```text
jaesung Vulkan:       0.714592 ms
Embree CUDA port:     1.066560 ms
VkRadixSort multi:   ≈2.250 ms p50
```

相对关系：

```text
jaesung Vulkan ≈ 1.49× faster than Embree CUDA port
jaesung Vulkan ≈ 3.15× faster than VkRadixSort multi p50
Embree CUDA port ≈ 2.11× faster than VkRadixSort multi p50
```

## 5.2 key-value

本轮只有 jaesung Vulkan 和 Embree CUDA port 有同 harness 的 key-value 数据：

```text
jaesung Vulkan:     0.812640 ms
Embree CUDA port:   1.360991 ms
```

相对关系：

```text
jaesung Vulkan ≈ 1.67× faster than Embree CUDA port
```

## 6. 为什么 jaesung-cs/vulkan_radix_sort 优势明显

主要原因是算法级别的工作量差异，而不是简单的 API 差异。

## 6.1 全局 prefix 只做一次

jaesung 的 `upsweep → spine → downsweep` 结构将 histogram prefix-sum 集中到 spine 阶段：

```text
histogram collection: upsweep
histogram prefix:     spine
scatter:              downsweep
```

scatter 阶段不需要每个 workgroup 重新计算大量历史 offset。

## 6.2 避免 per-workgroup 重复 histogram 扫描

`VkRadixSort` multi 的主要冗余来自每个 workgroup 在 scatter 前后重复处理 histogram offset。随着 workgroup 数量增加，这类重复访问会被放大。

相比之下，jaesung 的 spine 阶段把这些全局 offset 预先压缩成可直接使用的结果，scatter 阶段更轻。

## 6.3 更适合现代 GPU 的三阶段流水

三阶段结构把不同性质的工作拆开：

| 阶段 | 工作类型 | GPU 友好点 |
|---|---|---|
| upsweep | 局部 histogram | workgroup 内并行计数 |
| spine | 全局 prefix | 集中处理小规模 histogram 数据 |
| downsweep | scatter | 使用预计算 offset，减少重复全局访问 |

这种设计减少了 scatter 阶段的控制复杂度和全局内存冗余。

## 6.4 计时边界更干净

jaesung benchmark 使用 Vulkan timestamp 计 GPU 排序段。当前 Thor 上 timestamp period 为 `1`，因此 raw timestamp delta 可直接解释为 ns。

`VkRadixSort` example 使用 CPU wall-clock，包含 queue submit、wait idle 等额外成本，因此它的数值会更容易受 host/runtime 抖动影响。

## 7. 公平性与限制

本轮已经做到：

- 三者统一 `N = 1,048,576`。
- jaesung Vulkan 与 Embree CUDA port 使用同一个 benchmark driver。
- 两者都执行 1 warmup + 10 timed runs，并取 median。
- 两者都通过 CPU reference correctness check。
- Vulkan timestamp period 已核对为 `1`。

仍需注意：

1. **GPU contention**  
   本轮开始时 GPU util 接近 98%，存在其他 GPU-heavy 进程，因此结果可能受系统负载影响。

2. **VkRadixSort 计时口径不同**  
   VkRadixSort multi 结果来自原 example 的 wall-clock 输出，不是统一 harness 的 GPU timestamp median。

3. **Embree CUDA port 不是原始 Embree GPU 后端**  
   它是为了在 NVIDIA Thor 上运行而实现的 CUDA port，应标注为 port，而不是原始 Embree SYCL 性能。

4. **Embree 原始应用场景不同**  
   Embree PLOC 中 radix sort 常与 Morton code、BVH builder 数据结构绑定；本轮为了横向比较，使用通用 32-bit key/key-value workload。

## 8. 建议的后续实验

## 8.1 清空 GPU 干扰后重跑

建议在暂停其他 GPU-heavy 进程后重跑：

```bash
benchmark_repos/vulkan_radix_sort/build_embree_cuda/bench \
  vulkan /tmp/radix_vulkan.csv 1048576

benchmark_repos/vulkan_radix_sort/build_embree_cuda/bench \
  embree-cuda /tmp/radix_embree_cuda.csv 1048576

printf '0\n' | \
  benchmark_repos/VkRadixSort/build/multiradixsort/multiradixsortexample
```

## 8.2 给 VkRadixSort 增加同口径 GPU timestamp

为了更公平比较，建议将 `VkRadixSort` multi 接入统一 benchmark harness，或至少增加 Vulkan timestamp query：

- 同样 1 warmup + 10 timed runs。
- 输出 median/p95/max。
- 区分 GPU-only sort time 与 CPU wall time。
- 加入 correctness check。

## 8.3 增加多 N 曲线

建议规模：

```text
262144, 524288, 1048576, 2097152, 4194304, 8388608, 16777216
```

输出：

- GPU time vs N
- throughput vs N
- p50/p95/max vs N
- keys-only 与 key-value 分图

## 8.4 增加 Embree Morton64 fidelity benchmark

如果目标是评估 Embree PLOC 原始应用语境，应补充 Morton64 数据路径：

- 64-bit Morton code。
- Embree-style pass range。
- BVH/PLOC 相关 key layout。

该结果应与 32-bit 通用排序分开报告，避免混淆 apples-to-apples sort benchmark 与 Embree-fidelity benchmark。

## 9. 最终判断

在当前实测数据和代码结构分析下，三种方法的综合排序为：

```text
1. jaesung-cs/vulkan_radix_sort
2. Embree sort CUDA port
3. MircoWerner/VkRadixSort multi
```

`jaesung-cs/vulkan_radix_sort` 的优势主要来自算法 pipeline 的全局 work 分解：它把 histogram prefix 工作集中到 spine 阶段，scatter 阶段只消费预计算 offset，因此避免了 `VkRadixSort` multi 中大量 per-workgroup 重复 histogram offset 计算。

Embree CUDA port 的结果说明 Embree large radix sort 思路可以在 NVIDIA Thor 上正确运行，但当前 CUDA port 的三 kernel/pass 结构和原始 Embree SYCL 实现并非完全等价，性能也落后于 jaesung 的 Vulkan pipeline。

如果需要发布最终 benchmark，建议先在无 GPU contention 的环境下重跑，并为 `VkRadixSort` 增加同口径 GPU timestamp median 后再定稿。
