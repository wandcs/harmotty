import { describe, it, expect } from '@ohos/hypium'
import {
  DURABLE_ASSET_CHUNK_BYTES,
  DurableAssetFormat,
  DurableAssetManifest
} from '../main/ets/model/persistence/DurableAssetFormat'

export default function durableAssetFormatTest() {
  describe('DurableAssetFormat', () => {
    it('roundTripsMultiChunkUtf8Data', 0, () => {
      let text: string = 'Host prod\n  HostName example.com\n# 中文\n'.repeat(80)
      let encoded: Uint8Array = DurableAssetFormat.encodeText(text)
      let chunks: Uint8Array[] = DurableAssetFormat.split(encoded)
      expect(chunks.length > 1).assertEqual(true)
      for (let i = 0; i < chunks.length; i++) {
        expect(chunks[i].length <= DURABLE_ASSET_CHUNK_BYTES).assertEqual(true)
      }
      let combined: Uint8Array = DurableAssetFormat.combine(chunks)
      expect(DurableAssetFormat.decodeText(combined)).assertEqual(text)
    })

    it('serializesAndValidatesGenerationManifest', 0, () => {
      let value: Uint8Array = DurableAssetFormat.encodeText('retained-value')
      let manifest: DurableAssetManifest =
        DurableAssetFormat.createManifest('ssh/config', 'generation-1', value)
      let decoded: DurableAssetManifest =
        DurableAssetFormat.decodeManifest(DurableAssetFormat.encodeManifest(manifest))
      expect(decoded.path).assertEqual('ssh/config')
      expect(decoded.generation).assertEqual('generation-1')
      expect(decoded.chunkCount).assertEqual(1)
      expect(decoded.sha256.length).assertEqual(64)
      DurableAssetFormat.validate(decoded, value)
      expect(DurableAssetFormat.sha256(new Uint8Array(0)))
        .assertEqual('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')
    })

    it('rejectsCorruptedGenerationData', 0, () => {
      let value: Uint8Array = DurableAssetFormat.encodeText('original')
      let manifest: DurableAssetManifest =
        DurableAssetFormat.createManifest('ssh/known-hosts', 'generation-2', value)
      expect(() => {
        DurableAssetFormat.validate(manifest, DurableAssetFormat.encodeText('changed'))
      }).assertThrowError(Error)
    })
  })
}
