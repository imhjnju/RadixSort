# Radix Sort Clean Benchmark：2^21 附近性能实验与算法分析

生成日期：2026-05-13  
平台：NVIDIA Tegra Thor  
比较对象：

1. `jaesung-cs/vulkan_radix_sort`
2. `MircoWerner/VkRadixSort` multi variant
3. Embree `v4.0.0-ploc sort.h` CUDA port

## 1. 结论摘要

在 GPU 基本空闲的 clean 条件下重新测试后，之前“Embree 在 `N = 2^21` 更优”的结论不成立。clean 实验显示：

- keys-only：
  - `1M ~ 1.5M`：`VkRadixSort multi` 最快。
  - `2M` 及以上：`jaesung-cs/vulkan_radix_sort` 最快。
  - `Embree CUDA port` 在本轮 clean keys-only 测试中没有赢任何点。
- key-value：
  - `jaesung-cs/vulkan_radix_sort` 在所有测试规模都最快。
- 综合判断：
  - `jaesung-cs/vulkan_radix_sort` 是当前 NVIDIA Thor 上综合性能最好的方法。

最重要的修正是：此前高负载实验中 GPU utilization 约为 `98%`，导致 jaesung 在 `2^21` 点异常变慢；clean 条件下该异常消失，jaesung 曲线恢复平滑并在 `2^21` 领先。

## 2. 实验目标

本实验目标是确认：

1. 在 `N = 2^21` 附近，哪个 radix sort 实现性能更好。
2. 之前 Embree CUDA port 在 `2^21` 反超是否是稳定算法优势。
3. 不同算法性能差异来自算法结构，还是来自系统负载和测量口径。

## 3. 实验设计

### 3.1 测试规模

选择覆盖 `2^21` 附近的五个规模：

| 标签 | N |
|---|---:|
| `2^20` | 1,048,576 |
| `1.5 × 2^20` | 1,572,864 |
| `2^21` | 2,097,152 |
| `3 × 2^20` | 3,145,728 |
| `2^22` | 4,194,304 |

### 3.2 测试环境

| 项目 | 值 |
|---|---|
| GPU | NVIDIA Tegra NVIDIA Thor |
| Driver | 580.00 |
| CUDA | 13.0 / nvcc 13.0.48 |
| clean 测试前 GPU utilization | 0% |
| clean 测试后 GPU utilization | 4% |

这轮 clean 实验相比之前 `98% GPU utilization` 的实验更可信。

### 3.3 计时口径

主指标均使用 GPU-only 排序时间：

| 方法 | 计时方式 | 说明 |
|---|---|---|
| jaesung Vulkan | Vulkan timestamp | shared benchmark harness，1 warmup + 10 timed runs，取 median |
| Embree CUDA port | CUDA event | shared benchmark harness，1 warmup + 10 timed runs，取 median |
| VkRadixSort multi | Vulkan timestamp query | 每个 N 外部重复 10 次，取 `GPU_TIMESTAMP_RADIX_PASSES_SUM_MS` p50 |

不计入主指标：

- buffer upload
- CPU sort
- correctness verify download
- host submit/wait wall-clock

### 3.4 正确性 gate

- jaesung Vulkan：每个 N 都通过 CPU reference correctness check。
- Embree CUDA port：每个 N 都通过 CPU reference correctness check。
- VkRadixSort multi：每次运行都输出 `Test passed.`。

## 4. 输出文件

clean 实验输出文件：

```text
benchmark_repos/vulkan_radix_sort/build_embree_cuda/clean_2p21_vulkan.csv
benchmark_repos/vulkan_radix_sort/build_embree_cuda/clean_2p21_embree_cuda.csv
benchmark_repos/VkRadixSort/clean_2p21_vkradixsort_multi.csv
```

对比用的高负载实验文件：

```text
benchmark_repos/vulkan_radix_sort/build_embree_cuda/near_2p21_vulkan.csv
benchmark_repos/vulkan_radix_sort/build_embree_cuda/near_2p21_embree_cuda.csv
benchmark_repos/VkRadixSort/near_2p21_vkradixsort_multi.csv
```

## 5. Clean 实验结果：keys-only

| N | jaesung Vulkan | Embree CUDA port | VkRadixSort multi timestamp p50 | 最快 |
|---:|---:|---:|---:|---|
| 1,048,576 | 0.879136 ms | 1.152480 ms | 0.795984 ms | VkRadixSort multi |
| 1,572,864 | 1.124768 ms | 1.868319 ms | 1.024720 ms | VkRadixSort multi |
| 2,097,152 | 1.436800 ms | 2.793472 ms | 1.488275 ms | jaesung Vulkan |
| 3,145,728 | 2.087744 ms | 2.522720 ms | 2.700815 ms | jaesung Vulkan |
| 4,194,304 | 2.665184 ms | 3.324640 ms | 3.938275 ms | jaesung Vulkan |

### 5.1 keys-only 结论

```text
小规模 1M ~ 1.5M：VkRadixSort multi 最快。
2M 及以上：jaesung-cs/vulkan_radix_sort 最快。
Embree CUDA port 在 clean keys-only 测试中没有赢任何点。
```

在 `N = 2^21` 时：

```text
jaesung Vulkan:   1.436800 ms
VkRadixSort:      1.488275 ms
Embree CUDA port: 2.793472 ms
```

因此 clean 条件下，`2^21` keys-only 最快的是 `jaesung-cs/vulkan_radix_sort`。

## 6. Clean 实验结果：key-value

VkRadixSort multi 当前只测 keys-only，因此 key-value 只比较 jaesung Vulkan 和 Embree CUDA port。

| N | jaesung Vulkan kv | Embree CUDA port kv | 最快 |
|---:|---:|---:|---|
| 1,048,576 | 1.007456 ms | 1.535840 ms | jaesung Vulkan |
| 1,572,864 | 1.169952 ms | 2.554912 ms | jaesung Vulkan |
| 2,097,152 | 1.712704 ms | 2.395839 ms | jaesung Vulkan |
| 3,145,728 | 2.364544 ms | 3.598880 ms | jaesung Vulkan |
| 4,194,304 | 3.254688 ms | 5.195231 ms | jaesung Vulkan |

### 6.1 key-value 结论

```text
key-value 下 jaesung-cs/vulkan_radix_sort 全部测试规模最快。
```

key-value scatter 数据移动量更大，jaesung 的 `upsweep → spine → downsweep` pipeline 在该场景下优势更明显。

## 7. VkRadixSort multi 分布

VkRadixSort multi 每个 N 运行 10 次，以下为 GPU timestamp sum 的分布：

| N | min | p50 | max | max/min |
|---:|---:|---:|---:|---:|
| 1,048,576 | 0.696928 ms | 0.795984 ms | 0.957280 ms | 1.37× |
| 1,572,864 | 0.973984 ms | 1.024720 ms | 1.431870 ms | 1.47× |
| 2,097,152 | 1.345790 ms | 1.488275 ms | 1.706020 ms | 1.27× |
| 3,145,728 | 2.420580 ms | 2.700815 ms | 5.521950 ms | 2.28× |
| 4,194,304 | 3.752190 ms | 3.938275 ms | 7.782460 ms | 2.07× |

### 7.1 分布解读

VkRadixSort multi 在小规模很快，但在更大 N 下尾部明显：

```text
3M: max/min = 2.28×
4M: max/min = 2.07×
```

这说明它的 GPU 时间仍更容易受到调度、资源竞争或内部工作划分影响。即使使用 GPU timestamp 排除了 CPU wall-clock，尾部波动仍存在。

## 8. Clean vs 高负载实验对比

之前高负载实验开始和结束时 GPU utilization 约为 `98%`。在那轮实验中，`N = 2^21` keys-only 数据为：

| 方法 | 高负载 `2^21` keys-only |
|---|---:|
| jaesung Vulkan | 3.686912 ms |
| Embree CUDA port | 1.763615 ms |
| VkRadixSort multi | 3.669180 ms |

看起来 Embree 明显更快。

但 clean 条件下同一规模为：

| 方法 | clean `2^21` keys-only |
|---|---:|
| jaesung Vulkan | 1.436800 ms |
| VkRadixSort multi | 1.488275 ms |
| Embree CUDA port | 2.793472 ms |

结论完全反转。

### 8.1 为什么之前会误判 Embree 更优

高负载下 jaesung 在 `2^21` 点异常变慢：

```text
高负载 jaesung 2^21: 3.686912 ms
clean jaesung 2^21:  1.436800 ms
```

差距：

```text
约 2.57×
```

这说明之前 Embree 反超主要是系统负载污染造成的，不是稳定算法优势。

## 9. 算法结构分析

## 9.1 jaesung-cs/vulkan_radix_sort

核心结构：

```text
upsweep → spine → downsweep
```

### 优势

1. **全局 prefix 集中处理**
   - `upsweep` 统计局部 histogram。
   - `spine` 做全局 prefix-sum。
   - `downsweep` 使用预计算 offset scatter。

2. **scatter 阶段避免重复 offset 计算**
   - 每个 workgroup 不需要反复扫描全局 histogram。
   - 减少 global memory traffic。

3. **中大规模 scaling 稳定**
   - clean keys-only 中，从 `2M` 到 `4M` 都是最快。
   - key-value 全规模最快。

### 劣势或 caveat

- 在高 GPU 外部负载下，多阶段 Vulkan dispatch/barrier 可能受到干扰。
- 高负载实验中的 `2^21` 异常慢说明它对系统负载并非完全免疫。

## 9.2 VkRadixSort multi

### 优势

- 小规模 keys-only 很快。
- clean 条件下：

```text
1M:   0.795984 ms，最快
1.5M: 1.024720 ms，最快
```

说明它在小 N 下具有较低的 GPU execution overhead。

### 劣势

- 中大规模后不如 jaesung。
- 尾部波动明显。
- 可能存在 per-workgroup offset/histogram 处理重复工作。
- 当前只有 keys-only，没有同口径 key-value 结果。

### 适用判断

```text
VkRadixSort multi 适合小规模 keys-only；不适合作为中大规模或 key-value 的综合赢家。
```

## 9.3 Embree CUDA port

当前版本标注为：

```text
Embree v4.0.0-ploc radix_sort_Nx8Bit CUDA port (separate prefix kernel)
```

核心结构：

```text
binning kernel → build-offsets kernel → scatter kernel
```

32-bit key 需要 4 pass，因此约为：

```text
12 个 kernel
```

### 为什么 clean 条件下没有胜出

1. **kernel 数更多**
   - 每 pass 3 个 kernel。
   - 额外 prefix/offset kernel 增加同步与 launch 成本。

2. **separate prefix kernel 与 jaesung spine pipeline 不同**
   - 当前 CUDA port 不是原始 Embree SYCL large path 的完全等价实现。
   - 也不是高度融合的 GPU radix sort。

3. **key-value scatter 更重**
   - key-value 每元素移动 8 bytes。
   - Embree scatter/offset 结构在该 workload 下成本更高。

4. **256 DSS 上限限制大规模 scaling**
   - 当 N 继续增大，每个 DSS 处理更多元素。
   - 并行度不随 N 继续增长，单块工作变重。

### 适用判断

```text
Embree CUDA port 可正确运行，但当前移植版不是性能最优。
```

## 10. 最终结论

### 10.1 按 workload 分类

| 场景 | 最优方法 |
|---|---|
| 小规模 keys-only (`1M ~ 1.5M`) | VkRadixSort multi |
| 中大规模 keys-only (`2M+`) | jaesung-cs/vulkan_radix_sort |
| key-value | jaesung-cs/vulkan_radix_sort |
| 综合推荐 | jaesung-cs/vulkan_radix_sort |

### 10.2 一句话结论

```text
jaesung-cs/vulkan_radix_sort 综合最好；VkRadixSort multi 在小规模 keys-only 很快；Embree CUDA port 能正确运行但当前移植版不是性能赢家。
```

### 10.3 为什么 jaesung 综合更优

jaesung 的 `upsweep → spine → downsweep` 结构将 histogram prefix 工作集中处理，scatter 阶段直接消费预计算 offset，避免了大量 per-workgroup 重复 offset 计算，因此在中大规模和 key-value 下更稳定、更高效。

## 11. 后续建议

如果要进一步定稿为论文/报告级 benchmark，建议：

1. 每个后端每个 N 都做外部重复 10 次，统一报告 `min / p50 / p95 / max`。
2. 将 VkRadixSort multi 接入统一 CSV harness，避免手动改 `NUM_ELEMENTS` 重编译。
3. 为 VkRadixSort 增加 key-value 路径，才能完成完整 apples-to-apples 比较。
4. 对 jaesung 和 Embree 分阶段打 timestamp，拆出：
   - histogram/binning
   - prefix/spine/offset
   - scatter/downsweep
5. 对 high-load 与 clean-load 分别报告，明确区分算法性能和系统调度干扰。
