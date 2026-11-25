# PrivateType

**Why give your keyboard internet access just to type?**

PrivateType is an independent, offline keyboard for iOS and iPadOS 18 or later from SONNE SOLUTIONS (PTY) LTD.
Multilingual suggestions, spelling correction, and emoji search run on your device.
Choose QWERTY or QWERTZ. No Full Access, no account, no typing uploads, and no analytics.

## Keyboard privacy on iPhone and iPad

| Keyboard | Full Access | Examples of data sent to the provider | Sources |
| --- | --- | --- | --- |
| **PrivateType** | Never requested. | PrivateType sends no typing or usage data to its developer. | [Privacy policy](PRIVACY.md) |
| Google Gboard | Enables Google Search in the keyboard. | Gboard sends usage statistics, queries when you use Google Search, and audio when you use dictation. Saved words stay on your device. | [Google setup](https://support.google.com/gboard/answer/6380730?co=GENIE.Platform%3DiOS&hl=en), [Google privacy details](https://support.google.com/gboard/answer/9058584?co=GENIE.Platform%3DiOS&hl=en) |
| Microsoft SwiftKey | Requests Full Access for its full set of features. | SwiftKey can collect usage data. It saves learned words and your typing model to OneDrive if you enable Backup & Sync. It can send short typing samples if you opt in to help Microsoft improve SwiftKey. | [Microsoft setup](https://support.microsoft.com/en-us/swiftkey-keyboard/why-does-my-microsoft-swiftkey-keyboard-need-full-access-in-ios), [App Store privacy details](https://apps.apple.com/us/app/microsoft-swiftkey-ai-keyboard/id911813648), [OneDrive backup](https://support.microsoft.com/en-us/swiftkey-keyboard/swiftkey-backup-and-sync-with-onedrive), [Typing data FAQ](https://support.microsoft.com/en-us/swiftkey-keyboard/microsoft-swiftkey-keyboard-sharing-your-typing-data-faq) |

See [setup and support](SUPPORT.md) to start using PrivateType.

## Build from source

Use Xcode, Python 3, and Ruby with the `xcodeproj` gem.

```sh
python3 scripts/fetch_runtime.py
ruby scripts/generate_project.rb
open SimpleKeyboard.xcodeproj
```

Select the SimpleKeyboard scheme and an iOS simulator. Run the app and tap **Try the demo**. For device installation, select your development team and use your own bundle IDs.

The default build uses bundled dictionaries and phrase suggestions. You can supply compatible model files locally after you confirm their terms. For optional English neural prediction, provide `Models/English.pte` and `Models/EnglishVocabulary.txt` before project generation. See the [FUTO model repository](https://huggingface.co/futo-org/futo-swipe) and the [weights license](Models/FUTO-LICENSE.md).

## Test

Run `swift test` for portable core tests. Run `python3 scripts/run_simulator_tests.py` for iOS tests. The runner defaults to an iPhone 17 Pro simulator with iOS 26.2. Tests for optional assets skip when the assets are absent.

## Licenses

The original source code uses the [MIT license](LICENSE). The dictionary files use separate licenses. See [dictionary sources and notices](Dictionaries/README.md), the [Unicode license](docs/Unicode-License.txt), and the [ExecuTorch license](https://github.com/pytorch/executorch/blob/main/LICENSE).

The word hash uses Wang Yi's [wyhash](https://github.com/wangyi-fudan/wyhash/blob/master/wyhash.h) algorithm.
