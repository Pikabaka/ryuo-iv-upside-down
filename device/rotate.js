'use strict';

const Java = bridge;
Java.perform(() => {
  const Activity = 'com.baiyi.homeui.hshomeui.MainActivity';
  const Group = Java.use('android.view.ViewGroup');
  const Video = Java.use('android.view.SurfaceView');
  const Surface = Java.use('android.view.SurfaceControl');
  const Transaction = Java.use('android.view.SurfaceControl$Transaction');
  const Log = Java.use('android.util.Log');
  const field = Video.class.getDeclaredField('mSurfaceControl');
  field.setAccessible(true);

  function collect(view, videos) {
    if (!view.isShown() || view.getWidth() < 1 || view.getHeight() < 1) return;
    if (Video.class.isInstance(view)) {
      videos.push(Java.cast(view, Video));
    } else if (Group.class.isInstance(view)) {
      const group = Java.cast(view, Group);
      for (let i = 0; i < group.getChildCount(); i++) collect(group.getChildAt(i), videos);
    }
  }

  let current = null;
  let lastGeometry = '';
  function findActivity() {
    Java.choose(Activity, {
      onMatch(activity) {
        if (activity.isFinishing() || activity.isDestroyed()) return;
        current = Java.retain(activity);
        return 'stop';
      },
      onComplete() {}
    });
  }

  function update() {
    if (current !== null && (current.isFinishing() || current.isDestroyed())) {
      current.$dispose();
      current = null;
      lastGeometry = '';
    }
    if (current === null) findActivity();
    if (current === null) return;
    const decor = current.getWindow().getDecorView();
    const width = decor.getWidth();
    const height = decor.getHeight();
    if (!decor.isShown() || width !== 2240 || height !== 1080) return;
    const videos = [];
    collect(decor, videos);
    if (videos.length === 0) {
      lastGeometry = '';
      if (decor.getRotation() !== 180) decor.setRotation(180);
      return;
    }
    if (videos.length !== 1 || videos[0].getWidth() !== width || videos[0].getHeight() !== height) {
      return;
    }
    const video = videos[0];
    const obj = field.get(video);
    const frame = video.getHolder().getSurfaceFrame();
    const frameWidth = frame.width();
    const frameHeight = frame.height();
    if (obj === null || frameWidth < 1 || frameHeight < 1) return;
    const layer = Java.cast(obj, Surface);
    if (!layer.isValid()) return;
    const geometry = layer.toString() + ':' + frameWidth + ':' + frameHeight;
    if (geometry !== lastGeometry || decor.getRotation() !== 180) {
      if (decor.getRotation() !== 180) decor.setRotation(180);
      const tx = Transaction.$new();
      try {
        tx.setMatrix(layer, -width / frameWidth, 0, 0, -height / frameHeight);
        tx.setPosition(layer, width, height);
        tx.apply.overload('boolean').call(tx, true);
      } finally {
        tx.close();
      }
      lastGeometry = geometry;
      Log.i('RYUO180', 'Applied UI and video rotation: ' + frameWidth + 'x' + frameHeight);
    }
  }

  let pending = false;
  let lastError = '';
  function tick() {
    if (pending) return;
    pending = true;
    Java.scheduleOnMainThread(() => {
      try {
        update();
      } catch (error) {
        const text = String(error);
        if (text !== lastError) Log.e('RYUO180', text);
        lastError = text;
      } finally {
        pending = false;
      }
    });
  }
  tick();
  setInterval(tick, 2500);
});
