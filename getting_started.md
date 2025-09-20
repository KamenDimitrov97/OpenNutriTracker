# Getting started
## Android development with Windows 11
This IDE setup ist tested on Windows 11.

For setup first you need the following things:
- Android SDK and Android Emulator
- Flutter
- IDE like Android Studio or VS Code with Flutter Plugin installed.

Use paths for SDKs without spaces and sepcial characers.

### Setup Android SDK and Emulator
1. Download Android Studio from https://developer.android.com/studio and install. Keep "Android Virtual Device" checked. Start Android Studio after installation.

2. Install the Android SDK when asked.

3. After finishing the SDK installation you should the "Welcome to Android Studio" Screen. Click on "More Actions" -> "SDK Manager", switch to "SDK Tools" tab and check "Android SDK Command-line Tools (latest)", click "OK" and install the tools. 

4. Check under "More Actions" -> "Virtual Device Manager" if a virtual phone was set up, if not create one, e.g. a Medium Phone with Default Settings.

5. Close Android Studio.

### Setup Flutter SDK
1. Download Flutter 3.27.1 from https://docs.flutter.dev/install/archive and extract.

2. Add the bin folder in the folder where you extracted Flutter to the Path variable in "Advanced System Settings" -> "Environement Variables..." -> "System variables" -> "Path"

### Setup the Workspace in Visual Studio Code (VSC)
1. Create a new folder, open the folder in VSC.

2. Configure the Android SDK path for Flutter:

```flutter config --android-sdk "e:\path\to\androidSDK"```

3.⁠ ⁠Clone the repository with git in a VSC terminal (make sure the active folder in the terminal is your created folder from step 1):

```git clone https://github.com/simonoppowa/OpenNutriTracker.git .```

4.⁠ ⁠Get Dependencies.

```flutter pub get```

5.⁠ ⁠Run Build Runner to generate Files.

```flutter pub run build_runner build```

At the best revert all the visible generated files now, only env.g.dart is needed, it is not checked in because it is in .gitignore.

6.⁠ ⁠Restart VSC, VSC detects now that this is a flutter project. On the Bottom Right "No Device" ist displayed, click on it, then select "Start Medium Phone" on the command Palette on the top. Wait for the phone to boot up.

7. Press F5 to start a debug session (may taka a while on the first time). Keep the virtual phone running all the time, just start and stop Debugging.