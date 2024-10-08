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

#include <raft/neighbors/ivf_pq_types.hpp>

namespace raft::neighbors ::ivf_pq {

#define RAFT_INST_SEARCH(T, IdxT)   \
  void search(const handle_t&,      \
              const search_params&, \
              const index<IdxT>&,   \
              const T*,             \
              uint32_t,             \
              uint32_t,             \
              IdxT*,                \
              float*,               \
              rmm::mr::device_memory_resource*);

RAFT_INST_SEARCH(float, uint64_t);
RAFT_INST_SEARCH(int8_t, uint64_t);
RAFT_INST_SEARCH(uint8_t, uint64_t);

#undef RAFT_INST_SEARCH

// We define overloads for build and extend with void return type. This is used in the Cython
// wrappers, where exception handling is not compatible with return type that has nontrivial
// constructor.
#define RAFT_INST_BUILD_EXTEND(T, IdxT)      \
  auto build(const handle_t& handle,         \
             const index_params& params,     \
             const T* dataset,               \
             IdxT n_rows,                    \
             uint32_t dim)                   \
    ->index<IdxT>;                           \
                                             \
  auto extend(const handle_t& handle,        \
              const index<IdxT>& orig_index, \
              const T* new_vectors,          \
              const IdxT* new_indices,       \
              IdxT n_rows)                   \
    ->index<IdxT>;                           \
                                             \
  void build(const handle_t& handle,         \
             const index_params& params,     \
             const T* dataset,               \
             IdxT n_rows,                    \
             uint32_t dim,                   \
             index<IdxT>* idx);              \
                                             \
  void extend(const handle_t& handle,        \
              index<IdxT>* idx,              \
              const T* new_vectors,          \
              const IdxT* new_indices,       \
              IdxT n_rows);

RAFT_INST_BUILD_EXTEND(float, uint64_t)
RAFT_INST_BUILD_EXTEND(int8_t, uint64_t)
RAFT_INST_BUILD_EXTEND(uint8_t, uint64_t)

#undef RAFT_INST_BUILD_EXTEND

}  // namespace raft::neighbors::ivf_pq
