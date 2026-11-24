# PrivateType

PrivateType is an offline keyboard for iOS and iPadOS 18 or later. It offers multilingual suggestions, correction, and emoji search. Choose QWERTY or QWERTZ. The keyboard works with Full Access off.

See [setup and support](SUPPORT.md) and the [privacy policy](PRIVACY.md).

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
