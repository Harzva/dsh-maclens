// dsh-maclens — DeepSeek Harness plugin bridging Apple's on-device Vision
// framework (macOS) into dsh as tools. A text-only dsh model can read
// screenshots, scans, charts, and document pages through the local Vision
// engine: OCR, image classification, face detection, and document layout.
//
// The engine is a tiny Swift CLI compiled from swift/ inside this package
// (spawned per call, no daemon, no ports, no network). The plugin finds it
// next to its own install location, then by the MACLENS_BIN env var, then
// on PATH as `maclens`.
//
// Loaded via the cordis.patch.yml row `dsh-maclens` (see package.json
// `dsh.bundle`). No config file needed: everything lives in this package.
import { spawn } from 'node:child_process'
import { chmodSync, existsSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const PLUGIN_ROOT = dirname(fileURLToPath(import.meta.url))
const BIN_CANDIDATES = [
  process.env.MACLENS_BIN,
  join(PLUGIN_ROOT, '..', 'bin', 'maclens'),
  join(PLUGIN_ROOT, '..', 'swift', '.build', 'release', 'MaclensBridge'),
].filter(Boolean)

const CLI_TIMEOUT_MS = 120_000

export const name = 'dsh-maclens'
export const inject = ['tools']

function resolveBin() {
  for (const candidate of BIN_CANDIDATES) {
    if (existsSync(candidate)) {
      // npm tarballs can drop the executable bit; make sure it runs.
      try {
        chmodSync(candidate, 0o755)
      } catch {
        // not fatal — spawn will surface a real failure if it cannot run
      }
      return candidate
    }
  }
  // Last resort: a `maclens` on PATH.
  return 'maclens'
}

function run(bin, args, signal) {
  return new Promise((resolve) => {
    const child = spawn(bin, args, {
      stdio: ['ignore', 'pipe', 'pipe'],
      signal,
    })
    let stdout = ''
    let stderr = ''
    child.stdout.on('data', (chunk) => { stdout += chunk })
    child.stderr.on('data', (chunk) => { stderr += chunk })
    child.on('error', (error) => {
      resolve({ stdout, stderr, code: -1, error })
    })
    child.on('close', (code) => {
      resolve({ stdout, stderr, code })
    })
  })
}

function makeTool(name, description, properties, required, outputSchema, runTask) {
  return {
    name,
    description,
    parameters: {
      type: 'object',
      properties,
      required,
    },
    output: outputSchema
      ? { schema: outputSchema, render: (_args, value) => [{ type: 'text', text: JSON.stringify(value, null, 2) }] }
      : undefined,
    timeoutMs: CLI_TIMEOUT_MS + 20_000,
    isConcurrencySafe: () => true,
    presentCall: (args) => ({
      card: 'generic',
      title: name,
      kind: 'read',
      rawInput: args,
      ...(typeof args?.path === 'string' ? { locations: [{ path: args.path }] } : {}),
    }),
    async execute(args, exec) {
      if (typeof args?.path !== 'string' || args.path.trim() === '') {
        throw new Error(`${name} needs a non-empty string "path".`)
      }
      const bin = resolveBin()
      const cliArgs = [runTask, '--image', args.path]
      if (args.languages) {
        cliArgs.push('--languages', args.languages)
      }
      if (args.top) {
        cliArgs.push('--top', String(args.top))
      }
      if (args.maxLines) {
        cliArgs.push('--max-lines', String(args.maxLines))
      }
      const { stdout, stderr, code, error } = await run(bin, cliArgs, exec.signal)
      if (error) {
        throw new Error(`${name} could not run the maclens binary (${error.message}). Build it with: cd dsh-maclens/swift && swift build -c release`)
      }
      if (code !== 0) {
        throw new Error(`${name} failed (exit ${code}): ${(stderr || stdout).trim().slice(0, 500)}`)
      }
      let parsed
      try {
        parsed = JSON.parse(stdout)
      } catch {
        throw new Error(`${name} produced no JSON: ${stdout.trim().slice(0, 300)}`)
      }
      if (parsed.error) {
        throw new Error(`${name}: ${parsed.error}`)
      }
      return parsed
    },
  }
}

export function apply(ctx) {
  // OCR: transcribe all visible text with bounding boxes.
  try {
    ctx.tools.register(makeTool(
      'maclens_ocr',
      'Run Apple on-device Vision OCR on an image (local file path). Returns every visible text line with confidence and bounding box. Use for screenshots, scans, photos with text, or any image whose text the current model cannot read directly.',
      {
        path: { type: 'string', description: 'Absolute local path of the image' },
        languages: { type: 'string', description: 'Comma-separated recognition languages (default: zh-Hans,en-US)' },
      },
      ['path'],
      null,
      'ocr',
    ))
  } catch (error) {
    console.error(`[dsh-maclens] maclens_ocr registration skipped: ${error}`)
  }

  // Classification: what is in this image (1000+ categories).
  try {
    ctx.tools.register(makeTool(
      'maclens_classify',
      'Classify an image with Apple on-device Vision (local file path). Returns the top-N category identifiers with confidence (e.g. document, chart, diagram, photo). Use to identify what kind of image something is.',
      {
        path: { type: 'string', description: 'Absolute local path of the image' },
        top: { type: 'number', description: 'How many top categories to return (default 5)' },
      },
      ['path'],
      null,
      'classify',
    ))
  } catch (error) {
    console.error(`[dsh-maclens] maclens_classify registration skipped: ${error}`)
  }

  // Faces.
  try {
    ctx.tools.register(makeTool(
      'maclens_faces',
      'Detect faces in an image with Apple on-device Vision (local file path). Returns each face bounding box and confidence. Use to count people or locate faces in a photo.',
      {
        path: { type: 'string', description: 'Absolute local path of the image' },
      },
      ['path'],
      null,
      'faces',
    ))
  } catch (error) {
    console.error(`[dsh-maclens] maclens_faces registration skipped: ${error}`)
  }

  // Document: OCR + simple layout analysis.
  try {
    ctx.tools.register(makeTool(
      'maclens_document',
      'Parse a document page with Apple on-device Vision (local file path): OCR text plus a simple column layout analysis. Use for scanned pages, PDF renders, or multi-column documents.',
      {
        path: { type: 'string', description: 'Absolute local path of the image' },
        languages: { type: 'string', description: 'Comma-separated recognition languages (default: zh-Hans,en-US)' },
        maxLines: { type: 'number', description: 'Cap the number of OCR lines returned (for very tall screenshots)' },
      },
      ['path'],
      null,
      'document',
    ))
  } catch (error) {
    console.error(`[dsh-maclens] maclens_document registration skipped: ${error}`)
  }

  // Describe: one call combining OCR, classification, faces and layout.
  try {
    ctx.tools.register(makeTool(
      'maclens_describe',
      'Full Apple on-device Vision read of an image (local file path) in one call: OCR text, top category identifiers, face count, and a simple column layout. Use when you want a complete local picture of an image without extra round-trips. Note: Vision is a CV toolkit, not a vision-language model — it transcribes and classifies but does not produce free-form semantic description.',
      {
        path: { type: 'string', description: 'Absolute local path of the image' },
        languages: { type: 'string', description: 'Comma-separated recognition languages (default: zh-Hans,en-US)' },
        top: { type: 'number', description: 'How many top categories to return (default 5)' },
        maxLines: { type: 'number', description: 'Cap the number of OCR lines returned (for very tall screenshots)' },
      },
      ['path'],
      null,
      'describe',
    ))
  } catch (error) {
    console.error(`[dsh-maclens] maclens_describe registration skipped: ${error}`)
  }
}
