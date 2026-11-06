import Flutter
import UIKit
import UniformTypeIdentifiers

enum PasteControlPlugin {
  static func register(registrar: FlutterApplicationRegistrar) {
    registrar.register(
      PasteControlFactory(messenger: registrar.messenger()),
      withId: "loading/paste"
    )
  }
}

final class PasteControlFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    if #available(iOS 16.0, *) {
      return PasteControlPlatformView(frame: frame, viewId: viewId, messenger: messenger)
    }
    return EmptyPasteView(frame: frame)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

final class EmptyPasteView: NSObject, FlutterPlatformView {
  private let box: UIView

  init(frame: CGRect) {
    box = UIView(frame: frame)
    super.init()
  }

  func view() -> UIView {
    box
  }
}

@available(iOS 16.0, *)
final class PasteControlPlatformView: NSObject, FlutterPlatformView {
  private let host: PasteControlHost

  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "loading/paste/\(viewId)",
      binaryMessenger: messenger
    )
    host = PasteControlHost(frame: frame, channel: channel)
    super.init()
  }

  func view() -> UIView {
    host
  }
}

@available(iOS 16.0, *)
final class PasteControlHost: UIView {
  private let channel: FlutterMethodChannel

  init(frame: CGRect, channel: FlutterMethodChannel) {
    self.channel = channel
    super.init(frame: frame)
    backgroundColor = .clear
    let configuration = UIPasteControl.Configuration()
    configuration.displayMode = .iconOnly
    configuration.cornerStyle = .fixed
    configuration.cornerRadius = 10
    configuration.baseBackgroundColor = .clear
    configuration.baseForegroundColor = UIColor(
      red: 0.965,
      green: 0.941,
      blue: 0.902,
      alpha: 1
    )
    pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: [
      UTType.plainText.identifier,
      UTType.utf8PlainText.identifier,
      UTType.url.identifier,
    ])
    let control = UIPasteControl(configuration: configuration)
    control.translatesAutoresizingMaskIntoConstraints = false
    control.target = self
    addSubview(control)
    NSLayoutConstraint.activate([
      control.leadingAnchor.constraint(equalTo: leadingAnchor),
      control.trailingAnchor.constraint(equalTo: trailingAnchor),
      control.topAnchor.constraint(equalTo: topAnchor),
      control.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not used")
  }

  override func canPaste(_ itemProviders: [NSItemProvider]) -> Bool {
    itemProviders.contains { provider in
      provider.canLoadObject(ofClass: String.self) || provider.canLoadObject(ofClass: URL.self)
    }
  }

  override func paste(itemProviders: [NSItemProvider]) {
    read(itemProviders, at: 0)
  }

  private func read(_ providers: [NSItemProvider], at index: Int) {
    if index >= providers.count {
      deliver("")
      return
    }
    let provider = providers[index]
    if provider.canLoadObject(ofClass: String.self) {
      provider.loadObject(ofClass: String.self) { [weak self] object, _ in
        let text = (object as? String)?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty {
          self?.deliver(text)
          return
        }
        self?.readLink(provider) { link in
          if let link {
            self?.deliver(link)
          } else {
            self?.read(providers, at: index + 1)
          }
        }
      }
      return
    }
    readLink(provider) { [weak self] link in
      if let link {
        self?.deliver(link)
      } else {
        self?.read(providers, at: index + 1)
      }
    }
  }

  private func readLink(_ provider: NSItemProvider, done: @escaping (String?) -> Void) {
    guard provider.canLoadObject(ofClass: URL.self) else {
      done(nil)
      return
    }
    provider.loadObject(ofClass: URL.self) { object, _ in
      let link = (object as? URL)?.absoluteString
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if let link, !link.isEmpty {
        done(link)
      } else {
        done(nil)
      }
    }
  }

  private func deliver(_ text: String) {
    DispatchQueue.main.async { [weak self] in
      self?.channel.invokeMethod("pasted", arguments: text)
    }
  }
}
