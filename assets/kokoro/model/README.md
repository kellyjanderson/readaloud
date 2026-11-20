# Deprecated Kokoro Model Setup

Use this setup for legacy Kokoro compatibility and regression reproduction. For new speech work, see [MLX engine setup](../../../docs/mlx-tts-engines.md).

This directory is intentionally kept out of normal git history for the ONNX model file.

A Kokoro build or run expects this exact file path:

```text
assets/kokoro/model/kokoro-v1.0.onnx
```

## Suggested Sources

Use a compatible Kokoro ONNX model from a trusted upstream source such as:

- `thewh1teagle/kokoro-onnx` releases
- `hexgrad/Kokoro-82M`

Reference pages:

- https://github.com/thewh1teagle/kokoro-onnx/releases
- https://huggingface.co/hexgrad/Kokoro-82M

## Required Local Result

After download, the repository should contain:

```text
assets/
  kokoro/
    model/
      kokoro-v1.0.onnx
```

Do not commit the ONNX file to normal git history.
