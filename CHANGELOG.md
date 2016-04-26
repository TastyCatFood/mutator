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
