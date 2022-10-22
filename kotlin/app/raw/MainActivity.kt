package app.raw

import android.app.Activity
import android.os.Bundle

class MainActivity : Activity() {
    companion object {
        init {
            System.loadLibrary("raw")
        }
    }

    external fun hello(): String

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        getActionBar()!!.apply {
            setHomeButtonEnabled(true)
            setSubtitle(hello())
        }
    }
}
