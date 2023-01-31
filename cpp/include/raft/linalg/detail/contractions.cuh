/*
 * Copyright (c) 2022, NVIDIA CORPORATION.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#pragma once

#include <raft/util/device_loads_stores.cuh>

namespace raft {
namespace linalg {
namespace detail {

template <typename DataT, typename IdxT, typename Policy, bool isRowMajor = true>
struct Contractions_NT {
 protected:
  typedef Policy P;

  /** number of rows in X */
  IdxT m;
  /** number of rows in Y */
  IdxT n;
  /** number of columns in X and Y */
  IdxT k;
  /** leading dimension in X */
  IdxT lda;
  /** leading dimension in Y */
  IdxT ldb;
  /** leading dimension in Output D */
  IdxT ldd;

  /** current thread's global mem row id for X data */
  IdxT xrowid;
  /** current thread's global mem row id for Y data */
  IdxT yrowid;
  /** global memory pointer to X matrix */
  const DataT* x;
  /** global memory pointer to Y matrix */
  const DataT* y;

  /** current thread's smem row id */
  int srowid;
  /** current thread's smem column id */
  int scolid;
  /** current thread's accumulation row id */
  int accrowid;
  /** current thread's accumulation column id */
  int acccolid;

  /** base smem pointer for X data storage */
  DataT* sx;
  /** base smem pointer for Y data storage */
  DataT* sy;
  /** index pointing the correct smem page for writing after `ldgXY()` */
  int pageWr;
  /** index pointing the correct smem page for reading during `ldsXY()` */
  int pageRd;

  /** block of X data loaded from smem after `ldsXY()` */
  DataT regx[P::AccRowsPerTh][P::Veclen];
  /** block of Y data loaded from smem after `ldsXY()` */
  DataT regy[P::AccColsPerTh][P::Veclen];
  /** block of X data loaded from global mem after `ldgXY()` */
  DataT ldgDataX[P::LdgPerThX][P::Veclen];
  /** block of Y data loaded from global mem after `ldgXY()` */
  DataT ldgDataY[P::LdgPerThY][P::Veclen];

  static constexpr DataT Zero = (DataT)0;

 public:
  /**
   * @brief Ctor
   * @param[in] _x X matrix. [on device] [dim = _m x _k] [row-major]
   * @param[in] _y Y matrix. [on device] [dim = _n x _k] [row-major]
   * @param[in] _m number of rows of X
   * @param[in] _n number of rows of Y
   * @param[in] _k number of cols of X and Y
   * @param[in] _smem shared memory region used during computations
   */
  DI Contractions_NT(const DataT* _x, const DataT* _y, IdxT _m, IdxT _n, IdxT _k, char* _smem)
    : m(_m),
      n(_n),
      k(_k),
      lda(_k),
      ldb(_k),
      xrowid(IdxT(blockIdx.x) * P::Mblk + threadIdx.x / P::LdgThRow),
      yrowid(IdxT(blockIdx.y) * P::Nblk + threadIdx.x / P::LdgThRow),
      x(_x + xrowid * lda),
      y(_y + yrowid * ldb),
      srowid(threadIdx.x / P::LdgThRow),
      scolid((threadIdx.x % P::LdgThRow) * P::Veclen),
      accrowid(threadIdx.x / P::AccThCols),
      acccolid(threadIdx.x % P::AccThCols),
      sx((DataT*)_smem),
      sy(&(sx[P::SmemPageX])),
      pageWr(0),
      pageRd(0)
  {
  }

  /**
   * @brief Ctor
   * @param[in] _x X matrix. [on device] [dim = _m x _k] [row-major]
   * @param[in] _y Y matrix. [on device] [dim = _n x _k] [row-major]
   * @param[in] _m number of rows of X
   * @param[in] _n number of rows of Y
   * @param[in] _k number of cols of X and Y
   * @param[in] _smem shared memory region used during computations
   */
  DI Contractions_NT(const DataT* _x,
                     const DataT* _y,
                     IdxT _m,
                     IdxT _n,
                     IdxT _k,
                     IdxT _lda,
                     IdxT _ldb,
                     IdxT _ldd,
                     char* _smem)
    : m(_m),
      n(_n),
      k(_k),
      lda(_lda),
      ldb(_ldb),
      ldd(_ldd),
      srowid(threadIdx.x / P::LdgThRow),
      scolid((threadIdx.x % P::LdgThRow) * P::Veclen),
      accrowid(threadIdx.x / P::AccThCols),
      acccolid(threadIdx.x % P::AccThCols),
      sx((DataT*)_smem),
      sy(&(sx[P::SmemPageX])),
      pageWr(0),
      pageRd(0)
  {
    if (isRowMajor) {
      xrowid = IdxT(blockIdx.y) * P::Mblk + srowid;
      yrowid = IdxT(blockIdx.x) * P::Nblk + srowid;
      x      = _x + xrowid * lda;
      y      = _y + yrowid * ldb;
    } else {
      xrowid = IdxT(blockIdx.y) * P::Mblk;
      yrowid = IdxT(blockIdx.x) * P::Nblk;
      x      = _x + xrowid + srowid * lda;
      y      = _y + yrowid + srowid * ldb;
    }
  }

 protected:
  /**
   * @brief Load current block of X/Y from global memory to registers
   * @param[in] kidx current start index of k to be loaded
   */
  DI void ldgXY(IdxT kidx)
  {
    ldgX(kidx);
    ldgY(kidx);
  }

  /**
   * @brief Store current block of X/Y from registers to smem
   * @param[in] kidx current start index of k to be loaded
   */
  DI void stsXY()
  {
    stsX(sx + pageWr * P::SmemPage);
    stsY(sy + pageWr * P::SmemPage);
  }

  /**
   * @brief Load X and Y block from shared memory to registers
   * @param[in] kidx k value from the current k-block to be loaded from smem
   */
  DI void ldsXY(int kidx)
  {
    ldsX(kidx, sx + pageRd * P::SmemPage);
    ldsY(kidx, sy + pageRd * P::SmemPage);
  }

 private:
  DI void ldgX(IdxT kidx)
  {
    if (isRowMajor) {
      auto numRows = m;
      auto koffset = kidx + scolid;
#pragma unroll
      for (int i = 0; i < P::LdgPerThX; ++i) {
        if (koffset < lda && (xrowid + i * P::LdgRowsX) < numRows) {
          ldg(ldgDataX[i], x + i * P::LdgRowsX * lda + koffset);
        } else {
#pragma unroll
          for (int j = 0; j < P::Veclen; ++j) {
            ldgDataX[i][j] = Zero;
          }
        }
      }
    } else {
      const auto numRows = k;
      auto koffset       = scolid;
#pragma unroll
      for (int i = 0; i < P::LdgPerThX; ++i) {
        if ((koffset + xrowid) < lda && (srowid + kidx + i * P::LdgRowsX) < numRows) {
          ldg(ldgDataX[i], x + (kidx + i * P::LdgRowsX) * lda + koffset);
        } else {
#pragma unroll
          for (int j = 0; j < P::Veclen; ++j) {
            ldgDataX[i][j] = Zero;
          }
        }
      }
    }
  }

  DI void ldgY(IdxT kidx)
  {
    if (isRowMajor) {
      auto numRows = n;
      auto koffset = kidx + scolid;
#pragma unroll
      for (int i = 0; i < P::LdgPerThY; ++i) {
        if (koffset < ldb && (yrowid + i * P::LdgRowsY) < numRows) {
          ldg(ldgDataY[i], y + i * P::LdgRowsY * ldb + koffset);
        } else {
#pragma unroll
          for (int j = 0; j < P::Veclen; ++j) {
            ldgDataY[i][j] = Zero;
          }
        }
      }
    } else {
      auto numRows = k;
      auto koffset = scolid;
#pragma unroll
      for (int i = 0; i < P::LdgPerThY; ++i) {
        if ((koffset + yrowid) < ldb && (srowid + kidx + i * P::LdgRowsY) < numRows) {
          ldg(ldgDataY[i], y + (kidx + i * P::LdgRowsY) * ldb + koffset);
        } else {
#pragma unroll
          for (int j = 0; j < P::Veclen; ++j) {
            ldgDataY[i][j] = Zero;
          }
        }
      }
    }
  }

  DI void stsX(DataT* smem)
  {
    auto* saddr = smem + srowid * P::SmemStride + scolid;
#pragma unroll
    for (int i = 0; i < P::LdgPerThX; ++i) {
      sts(saddr + i * P::LdgRowsX * P::SmemStride, ldgDataX[i]);
    }
  }

  DI void stsY(DataT* smem)
  {
    auto* saddr = smem + srowid * P::SmemStride + scolid;
#pragma unroll
    for (int i = 0; i < P::LdgPerThY; ++i) {
      sts(saddr + i * P::LdgRowsY * P::SmemStride, ldgDataY[i]);
    }
  }

  DI void ldsX(int kidx, DataT* smem)
  {
    if (isRowMajor) {
      auto* saddr = smem + accrowid * P::SmemStride + kidx;
#pragma unroll
      for (int i = 0; i < P::AccRowsPerTh; ++i) {
        lds(regx[i], saddr + i * P::AccThRows * P::SmemStride);
      }
    } else {
      auto* saddr = smem + accrowid + kidx * P::SmemStride;
#pragma unroll
      for (int i = 0; i < P::AccRowsPerTh; ++i) {
#pragma unroll
        for (int v = 0; v < P::Veclen; ++v) {
          regx[i][v] = saddr[i * P::AccThRows + v * P::SmemStride];
        }
      }
    }
  }

  DI void ldsY(int kidx, DataT* smem)
  {
    if (isRowMajor) {
      auto* saddr = smem + acccolid * P::SmemStride + kidx;
#pragma unroll
      for (int i = 0; i < P::AccColsPerTh; ++i) {
        lds(regy[i], saddr + i * P::AccThCols * P::SmemStride);
      }
    } else {
      auto* saddr = smem + acccolid + kidx * P::SmemStride;
#pragma unroll
      for (int i = 0; i < P::AccColsPerTh; ++i) {
#pragma unroll
        for (int v = 0; v < P::Veclen; ++v) {
          regy[i][v] = saddr[i * P::AccThCols + v * P::SmemStride];
        }
      }
    }
  }

};  // struct Contractions_NT



template <typename DataT, typename IdxT, typename Policy, bool isRowMajor = true>
struct Contractions_NT_GF {
 protected:
  typedef Policy P;

  /** number of rows in X */
  IdxT m;
  /** number of rows in Y */
  IdxT n;
  /** number of columns in X and Y */
  IdxT k1, k2;
  /** leading dimension in X */
  IdxT lda1, lda2;
  /** leading dimension in Y */
  IdxT ldb1, ldb2;
  /** leading dimension in Output D */
  IdxT ldd;

  /** current thread's global mem row id for X data */
  IdxT xrowid;
  /** current thread's global mem row id for Y data */
  IdxT yrowid;
  /** global memory pointer to X matrix */
  const DataT* x1;
  /** global memory pointer to X matrix */
  const DataT* x2;
  /** global memory pointer to Y matrix */
  const DataT* y1;
  const DataT* y2;


  /** current thread's smem row id */
  int srowid;
  /** current thread's smem column id */
  int scolid;
  /** current thread's accumulation row id */
  int accrowid;
  /** current thread's accumulation column id */
  int acccolid;

  /** base smem pointer for X data storage (shared between x1,x2) */
  DataT* sx;
  /** base smem pointer for Y data storage (shared between y1 y2)*/
  DataT* sy;
  /** index pointing the correct smem page for writing after `ldgXY()` */
  int pageWr;
  /** index pointing the correct smem page for reading during `ldsXY()` */
  int pageRd;

  /** block of X data loaded from smem after `ldsXY()` ; (shared) */
  DataT regx1[P::AccRowsPerTh][P::Veclen];
  DataT regx2[P::AccRowsPerTh][P::Veclen];

  /** block of Y data loaded from smem after `ldsXY()` (shared) */
  DataT regy1[P::AccColsPerTh][P::Veclen];
  DataT regy2[P::AccColsPerTh][P::Veclen];

  /** block of X data loaded from global mem after `ldgXY()`  (shared) */
  DataT ldgDataX1[P::LdgPerThX][P::Veclen];
  DataT ldgDataX2[P::LdgPerThX][P::Veclen];

  /** block of Y data loaded from global mem after `ldgXY()` (shared) */
  DataT ldgDataY1[P::LdgPerThY][P::Veclen];
  DataT ldgDataY2[P::LdgPerThY][P::Veclen];

  static constexpr DataT Zero = (DataT)0;

 public:
  /**
   * @brief Ctor
   * @param[in] _x X matrix. [on device] [dim = _m x _k] [row-major]
   * @param[in] _y Y matrix. [on device] [dim = _n x _k] [row-major]
   * @param[in] _m number of rows of X
   * @param[in] _n number of rows of Y
   * @param[in] _k number of cols of X and Y
   * @param[in] _smem shared memory region used during computations
   */
  // DI Contractions_NT(const DataT* _x, const DataT* _y, IdxT _m, IdxT _n, IdxT _k, char* _smem)
  //   : m(_m),
  //     n(_n),
  //     k(_k),
  //     lda(_k),
  //     ldb(_k),
  //     xrowid(IdxT(blockIdx.x) * P::Mblk + threadIdx.x / P::LdgThRow),
  //     yrowid(IdxT(blockIdx.y) * P::Nblk + threadIdx.x / P::LdgThRow),
  //     x(_x + xrowid * lda),
  //     y(_y + yrowid * ldb),
  //     srowid(threadIdx.x / P::LdgThRow),
  //     scolid((threadIdx.x % P::LdgThRow) * P::Veclen),
  //     accrowid(threadIdx.x / P::AccThCols),
  //     acccolid(threadIdx.x % P::AccThCols),
  //     sx((DataT*)_smem),
  //     sy(&(sx[P::SmemPageX])),
  //     pageWr(0),
  //     pageRd(0)
  // {
  // }

  /**
   * @brief Ctor
   * @param[in] _x X matrix. [on device] [dim = _m x _k] [row-major]
   * @param[in] _y Y matrix. [on device] [dim = _n x _k] [row-major]
   * @param[in] _m number of rows of X
   * @param[in] _n number of rows of Y
   * @param[in] _k number of cols of X and Y
   * @param[in] _smem shared memory region used during computations
   */
  DI Contractions_NT_GF(const DataT* _x1,
                     const DataT* _x2,
                     const DataT* _y1,
                     const DataT* _y2,
                     IdxT _m,
                     IdxT _n,
                     IdxT _k1,
                     IdxT _k2,
                     IdxT _lda1,
                     IdxT _lda2,
                     IdxT _ldb1,
                     IdxT _ldb2,
                     IdxT _ldd,
                     char* _smem)
    : m(_m),
      n(_n),
      k1(_k1),
      k2(_k2),
      lda1(_lda1),
      lda2(_lda2),
      ldb1(_ldb1),
      ldb2(_ldb2),
      ldd(_ldd),
      srowid(threadIdx.x / P::LdgThRow),
      scolid((threadIdx.x % P::LdgThRow) * P::Veclen),
      accrowid(threadIdx.x / P::AccThCols),
      acccolid(threadIdx.x % P::AccThCols),
      sx((DataT*)_smem),
      sy(&(sx[P::SmemPageX])),
      pageWr(0),
      pageRd(0)
  {
    if (isRowMajor) {
      xrowid = IdxT(blockIdx.y) * P::Mblk + srowid;
      yrowid = IdxT(blockIdx.x) * P::Nblk + srowid;
      x1      = _x1 + xrowid * lda1;
      x2      = _x2 + xrowid * lda2;
      y1      = _y1 + yrowid * ldb1;
      y2      = _y2 + yrowid * ldb2;
    } else {
      xrowid = IdxT(blockIdx.y) * P::Mblk;
      yrowid = IdxT(blockIdx.x) * P::Nblk;
      x1      = _x1 + xrowid + srowid * lda1;
      x2      = _x2 + xrowid + srowid * lda2;
      y1      = _y1 + yrowid + srowid * ldb1;
      y2      = _y1 + yrowid + srowid * ldb2;
    }
  }

  

  // /**
  //  * @brief Ctor
  //  * @param[in] _x X matrix. [on device] [dim = _m x _k] [row-major]
  //  * @param[in] _y Y matrix. [on device] [dim = _n x _k] [row-major]
  //  * @param[in] _m number of rows of X
  //  * @param[in] _n number of rows of Y
  //  * @param[in] _k number of cols of X and Y
  //  * @param[in] _smem shared memory region used during computations
  //  */
  // DI Contractions_NT(const DataT* _x,
  //                    const DataT* _y,
  //                    IdxT _m,
  //                    IdxT _n,
  //                    IdxT _k,
  //                    IdxT _lda,
  //                    IdxT _ldb,
  //                    IdxT _ldd,
  //                    char* _smem)
  //   : m(_m),
  //     n(_n),
  //     k(_k),
  //     lda(_lda),
  //     ldb(_ldb),
  //     ldd(_ldd),
  //     srowid(threadIdx.x / P::LdgThRow),
  //     scolid((threadIdx.x % P::LdgThRow) * P::Veclen),
  //     accrowid(threadIdx.x / P::AccThCols),
  //     acccolid(threadIdx.x % P::AccThCols),
  //     sx((DataT*)_smem),
  //     sy(&(sx[P::SmemPageX])),
  //     pageWr(0),
  //     pageRd(0)
  // {
  //   if (isRowMajor) {
  //     xrowid = IdxT(blockIdx.y) * P::Mblk + srowid;
  //     yrowid = IdxT(blockIdx.x) * P::Nblk + srowid;
  //     x      = _x + xrowid * lda;
  //     y      = _y + yrowid * ldb;
  //   } else {
  //     xrowid = IdxT(blockIdx.y) * P::Mblk;
  //     yrowid = IdxT(blockIdx.x) * P::Nblk;
  //     x      = _x + xrowid + srowid * lda;
  //     y      = _y + yrowid + srowid * ldb;
  //   }
  // }

 protected:
  /**
   * @brief Load current block of X/Y from global memory to registers
   * @param[in] kidx current start index of k to be loaded
   */
  DI void ldgXY1(IdxT kidx)
  {
    ldgX1(kidx);
    ldgY1(kidx);
  }

    DI void ldgXY2(IdxT kidx)
  {
    ldgX2(kidx);
    ldgY2(kidx);
  }

  /**
  //  * @brief Store current block of X/Y from registers to smem
  //  * @param[in] kidx current start index of k to be loaded
  //  */
  DI void stsXY1()
  {
    stsX1(sx + pageWr * P::SmemPage);
    stsY1(sy + pageWr * P::SmemPage);
  }

    DI void stsXY2()
  {
    stsX2(sx + pageWr * P::SmemPage);
    stsY2(sy + pageWr * P::SmemPage);
  }


  /**
   * @brief Load X and Y block from shared memory to registers
   * @param[in] kidx k value from the current k-block to be loaded from smem
   */
  DI void ldsXY1(int kidx)
  {
    ldsX1(kidx, sx + pageRd * P::SmemPage);
    ldsY1(kidx, sy + pageRd * P::SmemPage);
  }

    /**
   * @brief Load X and Y block from shared memory to registers
   * @param[in] kidx k value from the current k-block to be loaded from smem
   */
  DI void ldsXY2(int kidx)
  {
    ldsX2(kidx, sx + pageRd * P::SmemPage);
    ldsY2(kidx, sy + pageRd * P::SmemPage);
  }


 private:
  DI void ldgX1(IdxT kidx)
  {
    if (isRowMajor) {
      auto numRows = m;
      auto koffset = kidx + scolid;
#pragma unroll
      for (int i = 0; i < P::LdgPerThX; ++i) {
        if (koffset < lda1 && (xrowid + i * P::LdgRowsX) < numRows) {
          ldg(ldgDataX1[i], x1 + i * P::LdgRowsX * lda1 + koffset);
        } else {
#pragma unroll
          for (int j = 0; j < P::Veclen; ++j) {
            ldgDataX1[i][j] = Zero;
          }
        }
      }
    } else {
      const auto numRows = k1;
      auto koffset       = scolid;
#pragma unroll
      for (int i = 0; i < P::LdgPerThX; ++i) {
        if ((koffset + xrowid) < lda1 && (srowid + kidx + i * P::LdgRowsX) < numRows) {
          ldg(ldgDataX1[i], x1 + (kidx + i * P::LdgRowsX) * lda1 + koffset);
        } else {
#pragma unroll
          for (int j = 0; j < P::Veclen; ++j) {
            ldgDataX1[i][j] = Zero;
          }
        }
      }
    }
  }

    DI void ldgX2(IdxT kidx)
  {
    if (isRowMajor) {
      auto numRows = m;
      auto koffset = kidx + scolid;
#pragma unroll
      for (int i = 0; i < P::LdgPerThX; ++i) {
        if (koffset < lda2 && (xrowid + i * P::LdgRowsX) < numRows) {
          ldg(ldgDataX2[i], x2 + i * P::LdgRowsX * lda2 + koffset);
        } else {
#pragma unroll
          for (int j = 0; j < P::Veclen; ++j) {
            ldgDataX2[i][j] = Zero;
          }
        }
      }
    } else {
      const auto numRows = k2;
      auto koffset       = scolid;
#pragma unroll
      for (int i = 0; i < P::LdgPerThX; ++i) {
        if ((koffset + xrowid) < lda2 && (srowid + kidx + i * P::LdgRowsX) < numRows) {
          ldg(ldgDataX2[i], x2 + (kidx + i * P::LdgRowsX) * lda2 + koffset);
        } else {
#pragma unroll
          for (int j = 0; j < P::Veclen; ++j) {
            ldgDataX2[i][j] = Zero;
          }
        }
      }
    }
  }

  DI void ldgY1(IdxT kidx)
  {
    if (isRowMajor) {
      auto numRows = n;
      auto koffset = kidx + scolid;
#pragma unroll
      for (int i = 0; i < P::LdgPerThY; ++i) {
        if (koffset < ldb1 && (yrowid + i * P::LdgRowsY) < numRows) {
          ldg(ldgDataY1[i], y1 + i * P::LdgRowsY * ldb1 + koffset);
        } else {
#pragma unroll
          for (int j = 0; j < P::Veclen; ++j) {
            ldgDataY1[i][j] = Zero;
          }
        }
      }
    } else {
      auto numRows = k1;
      auto koffset = scolid;
#pragma unroll
      for (int i = 0; i < P::LdgPerThY; ++i) {
        if ((koffset + yrowid) < ldb1 && (srowid + kidx + i * P::LdgRowsY) < numRows) {
          ldg(ldgDataY1[i], y1 + (kidx + i * P::LdgRowsY) * ldb1 + koffset);
        } else {
#pragma unroll
          for (int j = 0; j < P::Veclen; ++j) {
            ldgDataY1[i][j] = Zero;
          }
        }
      }
    }
  }

    DI void ldgY2(IdxT kidx)
  {
    if (isRowMajor) {
      auto numRows = n;
      auto koffset = kidx + scolid;
#pragma unroll
      for (int i = 0; i < P::LdgPerThY; ++i) {
        if (koffset < ldb2 && (yrowid + i * P::LdgRowsY) < numRows) {
          ldg(ldgDataY2[i], y2 + i * P::LdgRowsY * ldb2 + koffset);
        } else {
#pragma unroll
          for (int j = 0; j < P::Veclen; ++j) {
            ldgDataY2[i][j] = Zero;
          }
        }
      }
    } else {
      auto numRows = k2;
      auto koffset = scolid;
#pragma unroll
      for (int i = 0; i < P::LdgPerThY; ++i) {
        if ((koffset + yrowid) < ldb2 && (srowid + kidx + i * P::LdgRowsY) < numRows) {
          ldg(ldgDataY2[i], y2 + (kidx + i * P::LdgRowsY) * ldb2 + koffset);
        } else {
#pragma unroll
          for (int j = 0; j < P::Veclen; ++j) {
            ldgDataY2[i][j] = Zero;
          }
        }
      }
    }
  }

  DI void stsX1(DataT* smem)
  {
    auto* saddr = smem + srowid * P::SmemStride + scolid;
#pragma unroll
    for (int i = 0; i < P::LdgPerThX; ++i) {
      sts(saddr + i * P::LdgRowsX * P::SmemStride, ldgDataX1[i]);
    }
  }

    DI void stsX2(DataT* smem)
  {
    auto* saddr = smem + srowid * P::SmemStride + scolid;
#pragma unroll
    for (int i = 0; i < P::LdgPerThX; ++i) {
      sts(saddr + i * P::LdgRowsX * P::SmemStride, ldgDataX2[i]);
    }
  }

  DI void stsY1(DataT* smem)
  {
    auto* saddr = smem + srowid * P::SmemStride + scolid;
#pragma unroll
    for (int i = 0; i < P::LdgPerThY; ++i) {
      sts(saddr + i * P::LdgRowsY * P::SmemStride, ldgDataY1[i]);
    }
  }
    DI void stsY2(DataT* smem)
  {
    auto* saddr = smem + srowid * P::SmemStride + scolid;
#pragma unroll
    for (int i = 0; i < P::LdgPerThY; ++i) {
      sts(saddr + i * P::LdgRowsY * P::SmemStride, ldgDataY2[i]);
    }
  }

  DI void ldsX1(int kidx, DataT* smem)
  {
    if (isRowMajor) {
      auto* saddr = smem + accrowid * P::SmemStride + kidx;
#pragma unroll
      for (int i = 0; i < P::AccRowsPerTh; ++i) {
        lds(regx1[i], saddr + i * P::AccThRows * P::SmemStride);
      }
    } else {
      auto* saddr = smem + accrowid + kidx * P::SmemStride;
#pragma unroll
      for (int i = 0; i < P::AccRowsPerTh; ++i) {
#pragma unroll
        for (int v = 0; v < P::Veclen; ++v) {
          regx1[i][v] = saddr[i * P::AccThRows + v * P::SmemStride];
        }
      }
    }
  }

    DI void ldsX2(int kidx, DataT* smem)
  {
    if (isRowMajor) {
      auto* saddr = smem + accrowid * P::SmemStride + kidx;
#pragma unroll
      for (int i = 0; i < P::AccRowsPerTh; ++i) {
        lds(regx2[i], saddr + i * P::AccThRows * P::SmemStride);
      }
    } else {
      auto* saddr = smem + accrowid + kidx * P::SmemStride;
#pragma unroll
      for (int i = 0; i < P::AccRowsPerTh; ++i) {
#pragma unroll
        for (int v = 0; v < P::Veclen; ++v) {
          regx2[i][v] = saddr[i * P::AccThRows + v * P::SmemStride];
        }
      }
    }
  }


  DI void ldsY1(int kidx, DataT* smem)
  {
    if (isRowMajor) {
      auto* saddr = smem + acccolid * P::SmemStride + kidx;
#pragma unroll
      for (int i = 0; i < P::AccColsPerTh; ++i) {
        lds(regy1[i], saddr + i * P::AccThCols * P::SmemStride);
      }
    } else {
      auto* saddr = smem + acccolid + kidx * P::SmemStride;
#pragma unroll
      for (int i = 0; i < P::AccColsPerTh; ++i) {
#pragma unroll
        for (int v = 0; v < P::Veclen; ++v) {
          regy1[i][v] = saddr[i * P::AccThCols + v * P::SmemStride];
        }
      }
    }
  }

  DI void ldsY2(int kidx, DataT* smem)
  {
    if (isRowMajor) {
      auto* saddr = smem + acccolid * P::SmemStride + kidx;
#pragma unroll
      for (int i = 0; i < P::AccColsPerTh; ++i) {
        lds(regy2[i], saddr + i * P::AccThCols * P::SmemStride);
      }
    } else {
      auto* saddr = smem + acccolid + kidx * P::SmemStride;
#pragma unroll
      for (int i = 0; i < P::AccColsPerTh; ++i) {
#pragma unroll
        for (int v = 0; v < P::Veclen; ++v) {
          regy2[i][v] = saddr[i * P::AccThCols + v * P::SmemStride];
        }
      }
    }
  }

};  // struct Contractions_NT

}  // namespace detail
}  // namespace linalg
}  // namespace raft