# Radix Sort Manual Confirmation Summary
Output directory: `/home/robota/h00813233/Graph/RadixSort/benchmark_results/manual_confirm_20260525_142800`
## Keys-only winners
| N | jaesung ms | Embree ms | VkRadixSort p50 ms | winner |
|---:|---:|---:|---:|---|
| 1048576 | 0.812768 | 1.173632 | 0.728816 | vkr |
| 1572864 | 1.043584 | 1.416767 | 1.0017619999999998 | vkr |
| 2097152 | 1.455008 | 1.789152 | 1.3467799999999999 | vkr |
| 3145728 | 2.00672 | 2.509632 | 2.45802 | jaesung |
| 4194304 | 2.675584 | 3.263168 | 3.74158 | jaesung |

## Key-value winners
| N | jaesung ms | Embree ms | winner |
|---:|---:|---:|---|
| 1048576 | 0.933632 | 1.547327 | jaesung |
| 1572864 | 1.17072 | 1.88064 | jaesung |
| 2097152 | 1.702176 | 2.408832 | jaesung |
| 3145728 | 2.443808 | 3.646176 | jaesung |
| 4194304 | 3.238144 | 5.087423 | jaesung |

## VkRadixSort distribution
| N | min | p50 | max |
|---:|---:|---:|---:|
| 1048576 | 0.689568 | 0.728816 | 0.812640 |
| 1572864 | 0.962784 | 1.001762 | 1.135390 |
| 2097152 | 1.339970 | 1.346780 | 1.476350 |
| 3145728 | 2.421380 | 2.458020 | 2.804100 |
| 4194304 | 3.583100 | 3.741580 | 4.284990 |
