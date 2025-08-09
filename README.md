# UDP Master - Smart Home Visualizer


## Overview

UDP Master is a Flutter application designed to control and visualize smart home devices, particularly LED setups, using UDP communication. It allows users to discover, configure, and apply various visual effects to their devices, creating immersive and personalized lighting experiences. The application supports multiple platforms, including Android, iOS, and Linux.

## Features

*   **Device Discovery:** Automatically discover devices on your network using UDP broadcasts ([`BroadcastProtocol`](lib/services/discover.dart)).
*   **Device Management:**
    *   Add, edit, and remove devices with customizable names, IP addresses, port numbers, and LED counts.
    *   Organize and manage multiple devices within the application.
*   **Real-time Visualization:**
    *   Synchronize visual effects with audio input from the microphone.
    *   Screen capture functionality to sync the lights with the screen content ([`ScreenCapturePage`](lib/main.dart)).
*   **Customizable Effects:**
    *   Choose from a variety of pre-built visual effects, such as vertical bars, music rhythm, and center pulse.
    *   Adjust effect parameters like gain, brightness, and saturation to fine-tune the visual output.
*   **Wiz and WLED Support:**
    *   Control Wiz lighting devices using UDP commands ([`WizScreen`](lib/screen/wiz_screen.dart)).
    *   Fetch WLED details automatically ([`_fetchWledDetails`](lib/services/discover.dart)).
*   **Cross-Platform Compatibility:** Works on Android, iOS, and Linux.
*   **Persistence:** Save and load device configurations, effects, and display settings using shared preferences.
*   **Import/Export:** Import and export device configurations to JSON files for easy backup and sharing.
*   **Webview Integration:** Display device details in a WebView ([`DeviceDetails`](lib/screen/device_details.dart)).

## Screenshots

*Include screenshots of your application here to showcase its features and UI.*

## Setup Guide

Follow these steps to set up and run the UDP Master application:

### Prerequisites

*   [Flutter SDK](https://flutter.dev/docs/get-started/install)
*   [Android Studio](https://developer.android.com/studio) or [Xcode](https://developer.apple.com/xcode/) (for mobile development)
*   [CMake](https://cmake.org/download/) (for Linux development)

### Installation

1.  Clone the repository:

    ```sh
    git clone https://github.com/encrustace/udp_master.git
    cd udp_master
    ```

2.  Install dependencies:

    ```sh
    flutter pub get
    ```

### Configuration

1.  **Android Permissions:** The app requires microphone and network permissions. Ensure these are granted in the Android settings. The `AndroidManifest.xml` file ([android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml)) includes:

    ```xml
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
    <uses-permission android:name="android.permission.INTERNET" />
    ```

2.  **Linux Dependencies:** On Linux, ensure you have GTK and GLib installed.

    ```sh
    sudo apt-get update
    sudo apt-get install libgtk-3-dev libglib2.0-dev
    ```

### Running the Application

1.  **Android/iOS:**

    *   Connect an Android or iOS device, or start an emulator.
    *   Run the app using:

        ```sh
        flutter run
        ```

2.  **Linux:**

    *   Ensure you have the necessary dependencies installed (GTK, GLib).
    *   Run the app using:

        ```sh
        flutter run -d linux
        ```

### Usage

1.  **Device Discovery:** Use the device scan feature to automatically discover devices on your network.
2.  **Manual Configuration:** If automatic discovery fails, manually add devices by specifying their name, IP address, port, and LED count.
3.  **Effect Selection:** Choose an effect from the effects screen and customize its parameters.
4.  **Real-time Visualization:** Enable the visualizer to synchronize effects with audio input from your microphone or screen capture.

## Code Structure

*   `lib/main.dart`: Main application entry point.
*   `lib/models.dart`: Data models for devices, effects, and other application data.
*   `lib/screen/`: Contains the UI screens for the application, such as the home screen, device details, and effect configuration.
*   `lib/services/`: Includes services for device discovery, UDP communication, audio analysis, and data persistence.
*   `lib/effects/`: Defines the various visual effects that can be applied to the devices.

## Dependencies

The project uses the following dependencies:

*   `cupertino_icons`: For iOS-style icons.
*   `permission_handler`: For handling platform permissions.
*   `shared_preferences`: For persistent data storage.
*   `provider`: For state management.
*   `flutter_recorder`: For microphone input and audio recording.
*   `file_picker`: For importing and exporting device configurations.
*   `flutter_colorpicker`: For color selection.
*   `webview_flutter`: For displaying device details in a WebView.
*   `url_launcher`: For launching URLs.
*   `bonsoir`: For service discovery.
*   `flutter_webrtc`: For screen capture functionality.
*   `http`: For making HTTP requests.

## Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues to suggest improvements or report bugs.

## License

This project is licensed under the [MIT License](LICENSE).

## Author

Imran Khan
