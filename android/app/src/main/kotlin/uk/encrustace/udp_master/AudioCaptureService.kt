package uk.encrustace.udp_master

import android.app.*
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import android.Manifest
import android.content.pm.PackageManager
import kotlin.concurrent.thread
import android.os.Handler
import android.os.Looper


class AudioCaptureService : Service() {
    private var recordingThread: Thread? = null
    private var isRecording = false

    private fun hasAudioPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }

    @RequiresApi(Build.VERSION_CODES.O)
    override fun onCreate() {
        super.onCreate()
        val channel = NotificationChannel(
            "mic_channel",
            "Microphone Capture",
            NotificationManager.IMPORTANCE_LOW
        )
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
        val notification = Notification.Builder(this, "mic_channel")
            .setContentTitle("UDP Master")
            .setContentText("Capturing microphone in background")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .build()
        startForeground(1, notification)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startAudioCapture()
        return START_STICKY
    }

    private fun sendAudioToFlutter(samples: ShortArray, read: Int) {
        val floatSamples = DoubleArray(read) { samples[it].toDouble() / Short.MAX_VALUE }

    // Send result on main thread
    Handler(Looper.getMainLooper()).post {
        MainActivity.eventSink?.success(floatSamples.toList())
    }
    }

    private fun startAudioCapture() {
        if (isRecording) return

        if (!hasAudioPermission()) {
            Log.w("AudioCaptureService", "RECORD_AUDIO permission not granted!")
            stopSelf()
            return
        }

        isRecording = true
        recordingThread = thread(start = true) {
            val sampleRate = 44100
            val bufferSize = AudioRecord.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )
            var audioRecord: AudioRecord? = null
            try {
                audioRecord = AudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    sampleRate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    bufferSize
                )
                val buffer = ShortArray(bufferSize)
                audioRecord.startRecording()
                while (isRecording) {
                    val read = audioRecord.read(buffer, 0, buffer.size)
                    if (read > 0) {
                        sendAudioToFlutter(buffer, read)
                    }
                }
                audioRecord.stop()
            } catch (e: SecurityException) {
                Log.e("AudioCaptureService", "SecurityException: ${e.message}")
                stopSelf()
            } catch (e: IllegalArgumentException) {
                Log.e("AudioCaptureService", "IllegalArgumentException: ${e.message}")
                stopSelf()
            } finally {
                audioRecord?.release()
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        isRecording = false
        recordingThread?.join()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}