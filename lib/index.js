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
      if (args.slice) {
        cliArgs.push('--slice')
        if (args.sliceHeight) {
          cliArgs.push('--slice-height', String(args.sliceHeight))
        }
      }
      const { stdout, stderr, code, error } = await run(bin, cliArgs, exec.signal)
      if (error) {
        throw new Error(
          `${name}: the maclens binary could not run (${error.message}). ` +
          'Fix: build it with `cd dsh-maclens/swift && swift build -c release` ' +
          '(or install the npm package, which ships a prebuilt bin/maclens).'
        )
      }
      if (code === 2) {
        // Usage errors are our fault, not the caller's — surface the usage line.
        throw new Error(`${name}: ${(stdout || stderr).trim().slice(0, 300)}`)
      }
      if (code !== 0) {
        throw new Error(
          `${name} failed (exit ${code}) on ${args.path}: ` +
          `${(stderr || stdout).trim().slice(0, 500)}`
        )
      }
      let parsed
      try {
        parsed = JSON.parse(stdout)
      } catch {
        throw new Error(`${name} produced non-JSON output for ${args.path}: ${stdout.trim().slice(0, 300)}`)
      }
      if (parsed.error) {
        throw new Error(`${name} on ${args.path}: ${parsed.error}`)
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
      'Extract all visible text from an image using Apple on-device Vision (macOS, fully local). Pass the absolute file path; get back every text line with confidence and a normalized bbox. Use when a message references an image you cannot see and you need its text: screenshots, scans, photos with captions, charts with labels. For images taller than ~4000px (chat logs, scrolling captures) pass slice:true so small text is not lost.',
      {
        path: { type: 'string', description: 'Absolute local file path of the image' },
        languages: { type: 'string', description: 'Comma-separated recognition languages (default: zh-Hans,en-US)' },
        maxLines: { type: 'number', description: 'Cap the number of returned OCR lines (default: no cap)' },
        slice: { type: 'boolean', description: 'Split tall images into overlapping strips before OCR; set true for screenshots taller than ~4000px' },
        sliceHeight: { type: 'number', description: 'Strip height in pixels when slice is true (default 4096)' },
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
      'Identify what kind of image this is using Apple on-device Vision (macOS, fully local). Pass the absolute file path; get back top-N category identifiers with confidence (e.g. document, chart, diagram, photo, face). Use when you need to know the type/subject of an image before deeper processing.',
      {
        path: { type: 'string', description: 'Absolute local file path of the image' },
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
      'Detect faces in an image using Apple on-device Vision (macOS, fully local). Pass the absolute file path; get back each face bounding box (normalized) and confidence, plus a count. Use to locate people in a photo or verify whether faces are present.',
      {
        path: { type: 'string', description: 'Absolute local file path of the image' },
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
      'Parse a document page using Apple on-device Vision (macOS, fully local): OCR text plus a simple left/right column layout analysis and image dimensions. Pass the absolute file path. Use for scanned pages, PDF renders, or multi-column documents where column structure matters.',
      {
        path: { type: 'string', description: 'Absolute local file path of the image' },
        languages: { type: 'string', description: 'Comma-separated recognition languages (default: zh-Hans,en-US)' },
        maxLines: { type: 'number', description: 'Cap the number of returned OCR lines (default: no cap)' },
        slice: { type: 'boolean', description: 'Split tall images into overlapping strips before OCR; set true for screenshots taller than ~4000px' },
        sliceHeight: { type: 'number', description: 'Strip height in pixels when slice is true (default 4096)' },
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
      'One complete Apple on-device Vision read of an image (macOS, fully local): OCR text, top classification categories, face count, and column layout, in a single call. Pass the absolute file path. Use when you want the full local picture at once — then decide whether deeper analysis is needed. Note: Vision transcribes/classifies/detects; it does not produce free-form semantic description.',
      {
        path: { type: 'string', description: 'Absolute local file path of the image' },
        languages: { type: 'string', description: 'Comma-separated recognition languages (default: zh-Hans,en-US)' },
        top: { type: 'number', description: 'How many top categories to return (default 5)' },
        maxLines: { type: 'number', description: 'Cap the number of returned OCR lines (default: no cap)' },
        slice: { type: 'boolean', description: 'Split tall images into overlapping strips before OCR; set true for screenshots taller than ~4000px' },
        sliceHeight: { type: 'number', description: 'Strip height in pixels when slice is true (default 4096)' },
      },
      ['path'],
      null,
      'describe',
    ))
  } catch (error) {
    console.error(`[dsh-maclens] maclens_describe registration skipped: ${error}`)
  }
}
