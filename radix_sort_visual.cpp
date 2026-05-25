#include <array>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <vector>

static void print_array(const char* label, const std::vector<uint32_t>& data) {
    std::cout << label;
    for (uint32_t x : data) {
        std::cout << std::setw(4) << x;
    }
    std::cout << "\n";
}

static void print_selected_buckets(const std::array<size_t, 256>& values, const std::vector<size_t>& buckets) {
    for (size_t bucket : buckets) {
        std::cout << "[bucket " << std::setw(3) << bucket << " -> " << values[bucket] << "] ";
    }
    std::cout << "\n";
}

void radix_sort_visual(std::vector<uint32_t>& data) {
    constexpr size_t RADIX = 256;
    constexpr size_t MASK = RADIX - 1;

    std::vector<uint32_t> temp(data.size());

    print_array("start: ", data);

    for (size_t shift = 0; shift < 32; shift += 8) {
        std::array<size_t, RADIX> count{};
        std::vector<size_t> touched_buckets;

        std::cout << "\n=== pass shift = " << shift << ", byte = bits " << shift << ".." << shift + 7 << " ===\n";

        std::cout << "\n1) take digit from current byte\n";
        for (uint32_t x : data) {
            size_t digit = (x >> shift) & MASK;
            if (count[digit] == 0) {
                touched_buckets.push_back(digit);
            }
            count[digit]++;
            std::cout << "value " << std::setw(4) << x << " -> digit " << std::setw(3) << digit << "\n";
        }

        std::cout << "\n2) bucket frequency\n";
        print_selected_buckets(count, touched_buckets);

        size_t sum = 0;
        for (size_t i = 0; i < RADIX; ++i) {
            size_t c = count[i];
            count[i] = sum;
            sum += c;
        }

        std::cout << "\n3) bucket start position after prefix sum\n";
        print_selected_buckets(count, touched_buckets);

        std::cout << "\n4) stable scatter from left to right\n";
        for (uint32_t x : data) {
            size_t digit = (x >> shift) & MASK;
            size_t pos = count[digit]++;
            temp[pos] = x;
            std::cout << "place value " << std::setw(4) << x << " into temp[" << pos << "]\n";
        }

        data.swap(temp);
        print_array("after: ", data);
    }
}

int main() {
    std::vector<uint32_t> data = {170, 45, 75, 90, 802, 24, 2, 66};
    radix_sort_visual(data);
    return 0;
}
