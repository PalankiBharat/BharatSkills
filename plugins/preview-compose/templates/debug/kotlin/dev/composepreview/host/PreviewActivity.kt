package dev.composepreview.host

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * Renders any `@Preview` composable registered in [devicePreviewCallSites] by
 * FQN intent extra. Debug builds only.
 *
 * Launch:
 *   adb shell am start -n <applicationId>/dev.composepreview.host.PreviewActivity \
 *     --es preview.fqn '<pkg>.<FileKt>#<previewFunctionName>'
 *
 * A running activity accepts new FQNs via `startActivity` with the same intent
 * shape — see [onNewIntent]. Uses only compose-foundation primitives so the
 * activity doesn't depend on a specific Material version.
 */
class PreviewActivity : ComponentActivity() {

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContent { PreviewHost() }
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    setContent { PreviewHost() }
  }

  @Composable
  private fun PreviewHost() {
    var currentFqn by remember { mutableStateOf(intent.getStringExtra(PREVIEW_FQN_EXTRA)) }
    val fqn = currentFqn
    val callSite = fqn?.let { devicePreviewCallSites[it] }

    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
      when {
        fqn == null -> BasicText(
          text = "No preview.fqn intent extra provided.",
          modifier = Modifier.padding(24.dp),
        )
        callSite == null -> BasicText(
          text = "Preview not registered: $fqn\n" +
            "Re-run scripts/preview-compose.sh <file> to regenerate.",
          modifier = Modifier.padding(24.dp),
        )
        else -> callSite()
      }
    }
  }

  companion object {
    const val PREVIEW_FQN_EXTRA = "preview.fqn"
  }
}
