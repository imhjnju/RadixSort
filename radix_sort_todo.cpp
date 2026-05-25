#include <algorithm>
#include <array>
#include <cassert>
#include <cstdint>
#include <iostream>
#include <vector>

void radix_sort_u32(std::vector<uint32_t>& data) {
    constexpr size_t RADIX = 256;
    constexpr size_t MASK = RADIX - 1;

    std::vector<uint32_t> temp(data.size());

    for (size_t shift = 0; shift < 32; shift += 8) {
        std::array<size_t, RADIX> count{};

        // TODO 1: 统计当前 byte 的桶频率。
        // 提示：digit = (x >> shift) & MASK
        for (uint32_t x : data) {
            size_t digit = (x >> shift) & MASK;
            count[digit]++;
        }


        // TODO 2: 把 count 从“频率数组”变成“每个桶的起始位置”。
        // 提示：需要一个 running sum。
        size_t sum = 0;
        for (size_t i = 0; i < RADIX; i++) {
            size_t c = count[i];
            count[i] = sum;
            sum += c;
        }

        // TODO 3: 稳定 scatter 到 temp。
        // 提示：从左到右遍历 data，然后 temp[count[digit]++] = x;
        for (uint32_t x : data) {
            size_t digit = (x >> shift) & MASK;
            temp[count[digit]++] = x;
        }

        data.swap(temp);
    }
}

static void run_test(std::vector<uint32_t> input) {
    std::vector<uint32_t> expected = input;
    std::sort(expected.begin(), expected.end());

    radix_sort_u32(input);

    if (input != expected) {
        std::cerr << "Test failed.\nExpected: ";
        for (uint32_t x : expected) std::cerr << x << " ";
        std::cerr << "\nActual:   ";
        for (uint32_t x : input) std::cerr << x << " ";
        std::cerr << "\n";
        std::exit(1);
    }
}

int main() {
    run_test({});
    run_test({1});
    run_test({170, 45, 75, 90, 802, 24, 2, 66});
    run_test({0, 4294967295u, 1024, 256, 255, 1});
    run_test({5, 5, 5, 1, 1, 9, 0});
    run_test({256, 0, 65536, 255, 257, 1});
    run_test({3, 2, 1, 0});
    run_test({1000, 1, 989, 256, 255});

    std::cout << "All tests passed.\n";
    return 0;
}
