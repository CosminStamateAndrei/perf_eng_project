#ifndef PE_OPTS_H_
#define PE_OPTS_H_

#include <cstddef>
#include <cstdint>

#ifndef PF_DIST
#define PF_DIST 0
#endif

#ifdef USE_PAPI
#include <papi.h>
#define PE_REGION_BEGIN(name) PAPI_hl_region_begin(name)
#define PE_REGION_END(name)   PAPI_hl_region_end(name)
#else
#define PE_REGION_BEGIN(name) ((void)0)
#define PE_REGION_END(name)   ((void)0)
#endif

#if defined(USE_HUGEPAGES) && defined(__linux__)
#include <sys/mman.h>
inline void HugeAdvise(void *ptr, size_t bytes) {
  const uintptr_t kHuge = 2u << 20;
  if (bytes < kHuge)
    return;
  uintptr_t begin = (reinterpret_cast<uintptr_t>(ptr) + kHuge - 1) & ~(kHuge - 1);
  uintptr_t end = (reinterpret_cast<uintptr_t>(ptr) + bytes) & ~(kHuge - 1);
  if (end > begin)
    madvise(reinterpret_cast<void*>(begin), end - begin, MADV_HUGEPAGE);
}
#else
inline void HugeAdvise(void *, size_t) {}
#endif

#if defined(PE_THP_REPORT) && defined(__linux__)
#include <fstream>
#include <iostream>
#include <string>
inline void PEReportTHP() {
  std::ifstream f("/proc/self/smaps_rollup");
  std::string line;
  while (std::getline(f, line))
    if (line.rfind("AnonHugePages:", 0) == 0 || line.rfind("Rss:", 0) == 0)
      std::cout << "THP " << line << std::endl;
}
#else
inline void PEReportTHP() {}
#endif

#endif
