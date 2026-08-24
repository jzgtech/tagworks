package com.example.fontscale

import android.app.Activity
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot

class AndroidFontScalePlugin(godot: Godot) : GodotPlugin(godot) {

    override fun getPluginName(): String {
        return "AndroidFontScale"
    }

    @UsedByGodot
    fun getFontScale(): Float {
        return activity?.resources?.configuration?.fontScale ?: 1.0f
    }
}
