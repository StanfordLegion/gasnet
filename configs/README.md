The files in this directory contain the configure options for each canned config.

These options currently assume use of the following GASNet version range:

* GASNet-EX 2021.3.0 or later

Each file name identifies the (unique) GASNet conduit in use by that config.
The options in each config file are sorted for uniformity and readability
with following the convention:

1. Segment and threading options globally required by Realm
2. Conduit selection
3. PSHM (GASNet shared memory bypass) setting
4. MPI compatibility selection
5. Conduit-specific configure options
6. All other platform/config settings
 
