import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    testTimeout: 30_000,
    hookTimeout: 240_000,
    fileParallelism: false,
    coverage: { include: ['src/modules/**', 'src/ai/validate.ts', 'src/jobs/**'], thresholds: { lines: 80 } },
  },
});
