# =============================================================================
# Copyright (c) 2022, NVIDIA CORPORATION.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except
# in compliance with the License. You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed under the License
# is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
# or implied. See the License for the specific language governing permissions and limitations under
# the License.
# =============================================================================

include(${raft-dask-python_SOURCE_DIR}/cmake/thirdparty/get_nccl.cmake)

set(cython_sources comms_utils.pyx nccl.pyx)
set(linked_libraries raft::raft raft::distributed NCCL::NCCL)
rapids_cython_create_modules(
  SOURCE_FILES "${cython_sources}" ASSOCIATED_TARGETS raft LINKED_LIBRARIES "${linked_libraries}"
                                                                            CXX
)
