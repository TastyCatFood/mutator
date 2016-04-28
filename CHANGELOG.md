# Changelog

## 0.0.1

- Initial version

## 0.0.2
- A bug fixed

## 0.0.3
- mutate and mutate_t are now async methods.
 This change has been made as sometimes barback attempts to transform
 a part file before library's main file. Now, mutate_t only completes
 when dependencies are resolved.

##  0.0.4
- time_out_in_seconds option added to mutate_t and mutate.
 mutator function hangs when a part file is passed to mutate never
 its main library file is never passed; dependencies cannot be
 resolved.
 time_out_in_seconds is added to throw a warning when such occurs.
