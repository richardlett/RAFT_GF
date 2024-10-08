Cluster
=======

This page provides C++ class references for the publicly-exposed elements of the `raft/cluster` headers. RAFT provides
fundamental clustering algorithms which are, themselves, considered reusable building blocks for other algorithms.

.. role:: py(code)
   :language: c++
   :class: highlight

K-Means
#######

Header: `raft/cluster/kmeans.cuh`

.. doxygennamespace:: raft::cluster::kmeans
    :project: RAFT
    :members:
    :content-only:


Hierarchical Clustering
#######################

Header: `raft/cluster/single_linkage.cuh`

.. doxygennamespace:: raft::cluster::hierarchy
    :project: RAFT
    :members:
    :content-only:


Spectral Clustering
###################

Header: `raft/spectral/partition.cuh`

.. doxygennamespace:: raft::spectral
    :project: RAFT
    :members:
    :content-only:
