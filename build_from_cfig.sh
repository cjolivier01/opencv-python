#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CFIG_PATH="$ROOT_DIR/opencv/cfig"

usage() {
  cat <<'EOF'
Build opencv-python via setup.py, reusing the OpenCV CMake -D flags from opencv/cfig.

Usage:
  ./build_from_cfig.sh [options] [-- <extra setup.py args>...]

Options:
  --contrib            Set ENABLE_CONTRIB=1
  --headless           Set ENABLE_HEADLESS=1
  --java               Set ENABLE_JAVA=1
  --rolling            Set ENABLE_ROLLING=1
  --debug              Pass --build-type=Debug to setup.py
  --install            Install the built wheel (pip install -U dist/*.whl)
  --print-cmake-args   Print computed CMAKE_ARGS and exit
  -h, --help           Show this help

Notes:
  - Existing CMAKE_ARGS are appended after cfig flags (so they override).
  - Python/CMAKE_INSTALL_PREFIX flags from cfig are intentionally ignored; setup.py sets them.
EOF
}

want_contrib=0
want_headless=0
want_java=0
want_rolling=0
want_debug=0
want_install=0
print_cmake_args=0

setup_py_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --contrib) want_contrib=1; shift ;;
    --headless) want_headless=1; shift ;;
    --java) want_java=1; shift ;;
    --rolling) want_rolling=1; shift ;;
    --debug) want_debug=1; shift ;;
    --install) want_install=1; shift ;;
    --print-cmake-args) print_cmake_args=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; setup_py_args+=("$@"); break ;;
    *) setup_py_args+=("$1"); shift ;;
  esac
done

if [[ ! -f "$CFIG_PATH" ]]; then
  echo "error: missing $CFIG_PATH" >&2
  exit 1
fi

if [[ -z "${CMAKE_GENERATOR:-}" ]] && command -v ninja >/dev/null 2>&1; then
  export CMAKE_GENERATOR="Ninja"
fi

mapfile -t cfig_dflags < <(
  sed -n 's/[[:space:]]*\\\\$//; s/^[[:space:]]*//; /^-D/ p' "$CFIG_PATH" \
    | sed -E 's/^-D[[:space:]]+/-D/'
)

declare -A key_to_flag=()
keys_in_order=()

detect_contrib_from_cfig=0

for flag in "${cfig_dflags[@]}"; do
  key="${flag#-D}"
  key="${key%%=*}"

  case "$key" in
    CMAKE_INSTALL_PREFIX|PYTHON*|Python*|python*|OPENCV_PYTHON3_INSTALL_PATH|INSTALL_CREATE_DISTRIB)
      continue
      ;;
    OPENCV_EXTRA_MODULES_PATH)
      detect_contrib_from_cfig=1
      continue
      ;;
  esac

  if [[ -z "${key_to_flag[$key]+x}" ]]; then
    keys_in_order+=("$key")
  fi

  key_to_flag["$key"]="$flag"
done

if [[ "$detect_contrib_from_cfig" -eq 1 ]] && [[ -z "${ENABLE_CONTRIB:-}" ]] && [[ "$want_contrib" -eq 0 ]]; then
  want_contrib=1
fi

if [[ "$want_contrib" -eq 1 ]]; then export ENABLE_CONTRIB=1; fi
if [[ "$want_headless" -eq 1 ]]; then export ENABLE_HEADLESS=1; fi
if [[ "$want_java" -eq 1 ]]; then export ENABLE_JAVA=1; fi
if [[ "$want_rolling" -eq 1 ]]; then export ENABLE_ROLLING=1; fi

computed_cmake_args=()
for key in "${keys_in_order[@]}"; do
  computed_cmake_args+=("${key_to_flag[$key]}")
done

computed_cmake_args_str="$(printf '%s ' "${computed_cmake_args[@]}")"
computed_cmake_args_str="${computed_cmake_args_str% }"

if [[ -n "${CMAKE_ARGS:-}" ]]; then
  export CMAKE_ARGS="${computed_cmake_args_str} ${CMAKE_ARGS}"
else
  export CMAKE_ARGS="${computed_cmake_args_str}"
fi

if [[ "$print_cmake_args" -eq 1 ]]; then
  printf '%s\n' "$CMAKE_ARGS"
  exit 0
fi

cd "$ROOT_DIR"

if [[ "$want_debug" -eq 1 ]]; then
  python setup.py bdist_wheel --build-type=Debug "${setup_py_args[@]}"
else
  python setup.py bdist_wheel "${setup_py_args[@]}"
fi

if [[ "$want_install" -eq 1 ]]; then
  python -m pip install -U dist/*.whl
fi
