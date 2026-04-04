# Kokoro Model Setup

This directory is intentionally kept out of normal git history for the ONNX model file.

The app expects this exact file path before build or run:

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
