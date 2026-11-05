package com.loading.app.loading

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import java.nio.ByteBuffer

object TrackMux {
    fun combine(videoPath: String, audioPath: String, outputPath: String) {
        val video = MediaExtractor()
        val audio = MediaExtractor()
        var muxer: MediaMuxer? = null
        try {
            video.setDataSource(videoPath)
            audio.setDataSource(audioPath)
            val videoIndex = track(video, "video/")
            val audioIndex = track(audio, "audio/")
            video.selectTrack(videoIndex)
            audio.selectTrack(audioIndex)
            val writer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = writer
            val format = video.getTrackFormat(videoIndex)
            val rotation = if (format.containsKey(MediaFormat.KEY_ROTATION)) {
                format.getInteger(MediaFormat.KEY_ROTATION)
            } else {
                0
            }
            if (rotation != 0) writer.setOrientationHint(rotation)
            val videoTrack = writer.addTrack(video.getTrackFormat(videoIndex))
            val audioTrack = writer.addTrack(audio.getTrackFormat(audioIndex))
            writer.start()
            write(video, writer, videoTrack)
            write(audio, writer, audioTrack)
            writer.stop()
        } catch (error: Exception) {
            throw IllegalStateException(error.message ?: "รวมภาพกับเสียงไม่ได้", error)
        } finally {
            video.release()
            audio.release()
            try {
                muxer?.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun track(extractor: MediaExtractor, prefix: String): Int {
        for (index in 0 until extractor.trackCount) {
            val mime = extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)
            if (mime != null && mime.startsWith(prefix)) return index
        }
        throw IllegalStateException(
            if (prefix.startsWith("video")) "ไฟล์ภาพไม่มีแทร็กวิดีโอ" else "ไฟล์เสียงไม่มีแทร็กเสียง",
        )
    }

    private fun write(extractor: MediaExtractor, muxer: MediaMuxer, track: Int) {
        val buffer = ByteBuffer.allocate(8 * 1024 * 1024)
        val info = MediaCodec.BufferInfo()
        while (true) {
            val size = extractor.readSampleData(buffer, 0)
            if (size < 0) return
            info.offset = 0
            info.size = size
            info.presentationTimeUs = extractor.sampleTime
            info.flags = extractor.sampleFlags
            muxer.writeSampleData(track, buffer, info)
            extractor.advance()
        }
    }
}
