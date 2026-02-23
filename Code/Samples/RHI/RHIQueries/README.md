# RHIQueries

Demonstrates GPU query functionality for timing and occlusion.

## Features

- Timestamp queries for GPU timing
- Occlusion queries for visibility testing
- Query set creation and result readback

## Controls

| Key | Action |
|-----|--------|
| T | Toggle timestamp display |
| O | Toggle occlusion display |
| Space | Toggle occluded quad visibility |

## Technical Details

- Timestamp queries measure render pass execution time
- Occlusion queries count visible fragments
- Query results read back to CPU each frame
- Shows GPU time in milliseconds and visible sample count

## Dependencies

- Sedulous.RHI
- RHI.SampleFramework
