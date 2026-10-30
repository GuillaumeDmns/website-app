package com.guillaumedamiens.app

import android.app.Activity
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.SystemClock
import android.view.Surface
import io.flutter.plugin.common.EventChannel
import kotlin.math.atan2
import kotlin.math.hypot

/**
 * Where the phone points, in degrees clockwise from (magnetic) north, for GO's map on foot and by bike: the rotation
 * vector sensor (gyroscope, accelerometer and magnetometer fused by Android). Only while Dart listens (GO following
 * the user, the app on screen); at most 20 headings a second, smoothed on the Dart side, where the map glides between
 * them.
 */
class DeviceHeading(private val activity: Activity) : EventChannel.StreamHandler, SensorEventListener {

    private val sensorManager = activity.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val rotation = FloatArray(9)
    private var events: EventChannel.EventSink? = null
    private var lastSent = 0L

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        val sensor = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
            ?: sensorManager.getDefaultSensor(Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR)
        if (sensor == null) {
            // No compass: the map keeps the direction of the way
            sink.endOfStream()
            return
        }
        events = sink
        // About 16 a second (SENSOR_DELAY_UI): enough for the map to turn with the hand, a third of the game rate's
        // wake-ups
        sensorManager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_UI)
    }

    override fun onCancel(arguments: Any?) {
        sensorManager.unregisterListener(this)
        events = null
    }

    override fun onSensorChanged(event: SensorEvent) {
        val sink = events ?: return
        val now = SystemClock.elapsedRealtime()
        if (now - lastSent < MIN_INTERVAL_MS) return
        SensorManager.getRotationMatrixFromVector(rotation, event.values)
        // Device axes in the world (x east, y north, z up): the matrix's columns. Ahead is the top of the screen when
        // the phone is held flat, its back when held upright; tilted, both: their horizontal parts add up, so the
        // heading holds at any angle in between.
        val (upEast, upNorth) = when (screenRotation()) {
            Surface.ROTATION_90 -> rotation[0] to rotation[3] // Turned left: the screen's top is the device's right side
            Surface.ROTATION_180 -> -rotation[1] to -rotation[4]
            Surface.ROTATION_270 -> -rotation[0] to -rotation[3]
            else -> rotation[1] to rotation[4]
        }
        val east = upEast - rotation[2]
        val north = upNorth - rotation[5]
        if (hypot(east, north) < 0.1f) return // The two cancel out (phone held upside down): no direction this time
        val heading = Math.toDegrees(atan2(east, north).toDouble())
        lastSent = now
        sink.success((heading + 360.0) % 360.0)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    /** How the screen turned with the phone (Surface.ROTATION_…) */
    private fun screenRotation(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display?.rotation ?: Surface.ROTATION_0
        } else {
            @Suppress("DEPRECATION")
            activity.windowManager.defaultDisplay.rotation
        }

    companion object {
        const val CHANNEL = "com.guillaumedamiens.app/heading"
        private const val MIN_INTERVAL_MS = 50L
    }
}
