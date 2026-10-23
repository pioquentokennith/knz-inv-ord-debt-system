import android.content.Context;
import android.content.ContextWrapper;
import android.content.SharedPreferences;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;

/**
 * Exercises the notification plugin from an actual minified APK on Android.
 * All preferences are synthetic and in memory. This does not open the business
 * application's sandbox, initialize Flutter/Firebase, or post notifications.
 * See README.md in this directory for compilation and adb instructions.
 */
public final class NotificationReleaseProbe {
  private static final class MemoryContext extends ContextWrapper {
    final Map<String, String> values = new HashMap<>();
    final SharedPreferences preferences;

    MemoryContext() {
      super(null);
      SharedPreferences.Editor editor = (SharedPreferences.Editor) Proxy.newProxyInstance(
          NotificationReleaseProbe.class.getClassLoader(),
          new Class<?>[] {SharedPreferences.Editor.class},
          (proxy, method, args) -> {
            switch (method.getName()) {
              case "putString": values.put((String) args[0], (String) args[1]); return proxy;
              case "remove": values.remove((String) args[0]); return proxy;
              case "clear": values.clear(); return proxy;
              case "apply": return null;
              case "commit": return true;
              default: throw new UnsupportedOperationException(method.getName());
            }
          });
      preferences = (SharedPreferences) Proxy.newProxyInstance(
          NotificationReleaseProbe.class.getClassLoader(),
          new Class<?>[] {SharedPreferences.class},
          (proxy, method, args) -> {
            switch (method.getName()) {
              case "getString": return values.containsKey(args[0]) ? values.get(args[0]) : args[1];
              case "edit": return editor;
              default: throw new UnsupportedOperationException(method.getName());
            }
          });
    }

    @Override
    public SharedPreferences getSharedPreferences(String name, int mode) {
      if (!"scheduled_notifications".equals(name)) throw new AssertionError(name);
      return preferences;
    }
  }

  private static Object invoke(Method method, Object... args) throws Throwable {
    try {
      return method.invoke(null, args);
    } catch (InvocationTargetException error) {
      throw error.getCause();
    }
  }

  private static void check(boolean condition, String message) {
    if (!condition) throw new AssertionError(message);
  }

  public static void main(String[] args) {
    try {
      run();
    } catch (Throwable error) {
      error.printStackTrace(System.err);
      System.exit(1);
    }
  }

  private static void run() throws Throwable {
    Class<?> plugin = Class.forName(
        "com.dexterous.flutterlocalnotifications.FlutterLocalNotificationsPlugin");
    Method load = plugin.getDeclaredMethod("loadScheduledNotifications", Context.class);
    Method save = plugin.getDeclaredMethod("saveScheduledNotifications", Context.class, ArrayList.class);
    load.setAccessible(true);
    save.setAccessible(true);
    MemoryContext context = new MemoryContext();

    check(((ArrayList<?>) invoke(load, context)).isEmpty(), "Fresh cache must be empty");
    System.out.println("PASS: fresh notification cache");
    invoke(save, context, new ArrayList<>());
    check("[]".equals(context.values.get("scheduled_notifications")), "Save empty cache");
    check(((ArrayList<?>) invoke(load, context)).isEmpty(), "Read saved empty cache");
    System.out.println("PASS: saved empty cache reload (cancel/retry path)");

    context.values.put("scheduled_notifications", "[{\"id\":424242,"
        + "\"title\":\"Synthetic reminder\",\"body\":\"Synthetic body\","
        + "\"payload\":\"synthetic-scope\",\"channelId\":\"knz_overdue_debt\","
        + "\"timeZoneName\":\"Asia/Manila\",\"scheduledDateTime\":\"2026-12-01T09:00:00\","
        + "\"scheduleMode\":\"inexactAllowWhileIdle\"}]");
    for (int attempt = 0; attempt < 3; attempt++) {
      ArrayList<?> records = (ArrayList<?>) invoke(load, context);
      check(records.size() == 1, "Retain one scheduled reminder");
      Object record = records.get(0);
      Class<?> type = record.getClass();
      check(Integer.valueOf(424242).equals(type.getField("id").get(record)), "Retain ID");
      check("synthetic-scope".equals(type.getField("payload").get(record)), "Retain payload");
      check("Asia/Manila".equals(type.getField("timeZoneName").get(record)), "Retain timezone");
      check("inexactAllowWhileIdle".equals(type.getField("scheduleMode").get(record).toString()),
          "Retain schedule mode");
      invoke(save, context, records);
    }
    System.out.println("PASS: scheduled reminder survives three serialization/retry cycles");
    invoke(save, context, new ArrayList<>());
    check(((ArrayList<?>) invoke(load, context)).isEmpty(), "Read cleared cache");
    System.out.println("PASS: cleared cache remains readable");
  }
}
