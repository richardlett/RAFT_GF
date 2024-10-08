# =============================================================================
# Copyright (c) 2021-2022, NVIDIA CORPORATION.
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

# ##################################################################################################
# * compiler function -----------------------------------------------------------------------------

function(ConfigureTest)

  set(options OPTIONAL DIST NN)
  set(oneValueArgs NAME)
  set(multiValueArgs PATH TARGETS CONFIGURATIONS)

  cmake_parse_arguments(ConfigureTest "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  set(TEST_NAME ${ConfigureTest_NAME})

  add_executable(${TEST_NAME} ${ConfigureTest_PATH})

  message("TEST PATH: ${ConfigureTest_PATH}")

  target_link_libraries(
    ${TEST_NAME}
    PRIVATE raft::raft
            $<$<BOOL:${ConfigureTest_DIST}>:raft::distance>
            $<$<BOOL:${ConfigureTest_NN}>:raft::nn>
            GTest::gtest
            GTest::gtest_main
            Threads::Threads
            $<TARGET_NAME_IF_EXISTS:OpenMP::OpenMP_CXX>
            $<TARGET_NAME_IF_EXISTS:conda_env>
  )

  add_test(NAME ${TEST_NAME} COMMAND ${TEST_NAME})

  set_target_properties(
    ${TEST_NAME}
    PROPERTIES # set target compile options
               INSTALL_RPATH "\$ORIGIN/../../../lib"
               CXX_STANDARD 17
               CXX_STANDARD_REQUIRED ON
               CUDA_STANDARD 17
               CUDA_STANDARD_REQUIRED ON
  )

  target_compile_options(
    ${TEST_NAME} PRIVATE "$<$<COMPILE_LANGUAGE:CXX>:${RAFT_CXX_FLAGS}>"
                         "$<$<COMPILE_LANGUAGE:CUDA>:${RAFT_CUDA_FLAGS}>"
  )

  target_include_directories(${TEST_NAME} PUBLIC "$<BUILD_INTERFACE:${RAFT_SOURCE_DIR}/test>")

  install(
    TARGETS ${TEST_NAME}
    COMPONENT testing
    DESTINATION bin/gtests/libraft
    EXCLUDE_FROM_ALL
  )
endfunction()

# ##################################################################################################
# test sources ##################################################################################
# ##################################################################################################

# ##################################################################################################
# * distance tests -------------------------------------------------------------------------

if(BUILD_TESTS)
  ConfigureTest(
    NAME CLUSTER_TEST PATH test/cluster/kmeans.cu test/cluster_solvers.cu test/cluster/linkage.cu
    OPTIONAL DIST NN
  )

  ConfigureTest(
    NAME
    CORE_TEST
    PATH
    test/common/logger.cpp
    test/handle.cpp
    test/interruptible.cu
    test/nvtx.cpp
    test/mdarray.cu
    test/mdspan_utils.cu
    test/memory_type.cpp
    test/span.cpp
    test/span.cu
    test/test.cpp
  )

  ConfigureTest(
    NAME
    DISTANCE_TEST
    PATH
    test/distance/dist_adj.cu
    test/distance/dist_canberra.cu
    test/distance/dist_chebyshev.cu
    test/distance/dist_correlation.cu
    test/distance/dist_cos.cu
    test/distance/dist_euc_exp.cu
    test/distance/dist_euc_unexp.cu
    test/distance/dist_eucsqrt_exp.cu
    test/distance/dist_hamming.cu
    test/distance/dist_hellinger.cu
    test/distance/dist_jensen_shannon.cu
    test/distance/dist_kl_divergence.cu
    test/distance/dist_l1.cu
    test/distance/dist_minkowski.cu
    test/distance/dist_russell_rao.cu
    test/distance/fused_l2_nn.cu
    test/distance/gram.cu
    OPTIONAL
    DIST
  )

  ConfigureTest(NAME LABEL_TEST PATH test/label/label.cu test/label/merge_labels.cu)

  ConfigureTest(
    NAME
    LINALG_TEST
    PATH
    test/linalg/add.cu
    test/linalg/axpy.cu
    test/linalg/binary_op.cu
    test/linalg/cholesky_r1.cu
    test/linalg/coalesced_reduction.cu
    test/linalg/divide.cu
    test/linalg/dot.cu
    test/linalg/eig.cu
    test/linalg/eig_sel.cu
    test/linalg/gemm_layout.cu
    test/linalg/gemv.cu
    test/linalg/map.cu
    test/linalg/map_then_reduce.cu
    test/linalg/matrix_vector.cu
    test/linalg/matrix_vector_op.cu
    test/linalg/mean_squared_error.cu
    test/linalg/multiply.cu
    test/linalg/norm.cu
    test/linalg/normalize.cu
    test/linalg/power.cu
    test/linalg/reduce.cu
    test/linalg/reduce_cols_by_key.cu
    test/linalg/reduce_rows_by_key.cu
    test/linalg/rsvd.cu
    test/linalg/sqrt.cu
    test/linalg/strided_reduction.cu
    test/linalg/subtract.cu
    test/linalg/svd.cu
    test/linalg/ternary_op.cu
    test/linalg/transpose.cu
    test/linalg/unary_op.cu
  )

  ConfigureTest(
    NAME
    MATRIX_TEST
    PATH
    test/matrix/argmax.cu
    test/matrix/argmin.cu
    test/matrix/columnSort.cu
    test/matrix/diagonal.cu
    test/matrix/gather.cu
    test/matrix/linewise_op.cu
    test/matrix/math.cu
    test/matrix/matrix.cu
    test/matrix/norm.cu
    test/matrix/reverse.cu
    test/matrix/slice.cu
    test/matrix/triangular.cu
    test/spectral_matrix.cu
  )

  ConfigureTest(
    NAME
    RANDOM_TEST
    PATH
    test/random/make_blobs.cu
    test/random/make_regression.cu
    test/random/multi_variable_gaussian.cu
    test/random/permute.cu
    test/random/rng.cu
    test/random/rng_int.cu
    test/random/rmat_rectangular_generator.cu
    test/random/sample_without_replacement.cu
  )

  ConfigureTest(
    NAME SOLVERS_TEST PATH test/cluster_solvers_deprecated.cu test/eigen_solvers.cu test/lap/lap.cu
    test/mst.cu OPTIONAL DIST
  )

  ConfigureTest(
    NAME
    SPARSE_TEST
    PATH
    test/sparse/add.cu
    test/sparse/convert_coo.cu
    test/sparse/convert_csr.cu
    test/sparse/csr_row_slice.cu
    test/sparse/csr_to_dense.cu
    test/sparse/csr_transpose.cu
    test/sparse/degree.cu
    test/sparse/filter.cu
    test/sparse/norm.cu
    test/sparse/reduce.cu
    test/sparse/row_op.cu
    test/sparse/sort.cu
    test/sparse/spgemmi.cu
    test/sparse/symmetrize.cu
  )

  ConfigureTest(
    NAME SPARSE_DIST_TEST PATH test/sparse/dist_coo_spmv.cu test/sparse/distance.cu OPTIONAL DIST
    NN
  )

  ConfigureTest(
    NAME SPARSE_NEIGHBORS_TEST PATH test/sparse/neighbors/connect_components.cu
    test/sparse/neighbors/brute_force.cu test/sparse/neighbors/knn_graph.cu OPTIONAL DIST NN
  )

  ConfigureTest(
    NAME
    NEIGHBORS_TEST
    PATH
    test/neighbors/ann_ivf_flat.cu
    test/neighbors/ann_ivf_pq/test_float_int64_t.cu
    test/neighbors/ann_ivf_pq/test_float_uint32_t.cu
    test/neighbors/ann_ivf_pq/test_float_uint64_t.cu
    test/neighbors/ann_ivf_pq/test_int8_t_uint64_t.cu
    test/neighbors/ann_ivf_pq/test_uint8_t_uint64_t.cu
    test/neighbors/knn.cu
    test/neighbors/fused_l2_knn.cu
    test/neighbors/haversine.cu
    test/neighbors/ball_cover.cu
    test/neighbors/epsilon_neighborhood.cu
    test/neighbors/faiss_mr.cu
    test/neighbors/refine.cu
    test/neighbors/selection.cu
    OPTIONAL
    DIST
    NN
  )

  ConfigureTest(
    NAME
    STATS_TEST
    PATH
    test/stats/accuracy.cu
    test/stats/adjusted_rand_index.cu
    test/stats/completeness_score.cu
    test/stats/contingencyMatrix.cu
    test/stats/cov.cu
    test/stats/dispersion.cu
    test/stats/entropy.cu
    test/stats/histogram.cu
    test/stats/homogeneity_score.cu
    test/stats/information_criterion.cu
    test/stats/kl_divergence.cu
    test/stats/mean.cu
    test/stats/meanvar.cu
    test/stats/mean_center.cu
    test/stats/minmax.cu
    test/stats/mutual_info_score.cu
    test/stats/r2_score.cu
    test/stats/rand_index.cu
    test/stats/regression_metrics.cu
    test/stats/silhouette_score.cu
    test/stats/stddev.cu
    test/stats/sum.cu
    test/stats/trustworthiness.cu
    test/stats/weighted_mean.cu
    test/stats/v_measure.cu
    OPTIONAL
    DIST
    NN
  )

  ConfigureTest(
    NAME UTILS_TEST PATH test/common/seive.cu test/cudart_utils.cpp test/device_atomics.cu
    test/integer_utils.cpp test/pow2_utils.cu
  )
endif()
