//
//  iOSAccessoryView.swift
//  
//  Implements an inputAccessoryView for the iOS terminal for common operations
//
//  Created by Miguel de Icaza on 5/9/20.
//
#if os(iOS) || os(visionOS)

import Foundation
import UIKit

/**
 * This class provides an input accessory for the terminal on iOS, you can access this via the `inputAccessoryView`
 * property in the `TerminalView` and casting the result to `TerminalAccessory`.
 *
 * This class surfaces some state that the terminal might want to poke at, you should at least support the following
 * properties;
 * `controlModifer` should be set if the control key is pressed
 */
public class TerminalAccessory: UIInputView, UIInputViewAudioFeedback {
    /// This points to an instanace of the `TerminalView` where events are sent
    public weak var terminalView: TerminalView?
    weak var terminal: Terminal?
    var controlButton: UIButton?
    /// This tracks whether the "control" button is turned on or not
    public var controlModifier: Bool = false {
        didSet {
            controlButton?.isSelected = controlModifier
        }
    }
    
    var touchButton: UIButton!
    var keyboardButton: UIButton!
    
    var views: [UIView] = []
    
    public init (frame: CGRect, inputViewStyle: UIInputView.Style, container: TerminalView)
    {
        self.terminalView = container
        self.terminal = terminalView?.getTerminal()
        super.init (frame: frame, inputViewStyle: inputViewStyle)
        allowsSelfSizing = true
    }
    
    public override var bounds: CGRect {
        didSet {
            setupUI ()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    #if os(iOS)
    // Override for UIInputViewAudioFeedback
    public var enableInputClicksWhenVisible: Bool { true }
    #endif
    
    func clickAndSend (_ data: [UInt8])
    {
        #if os(iOS)
        UIDevice.current.playInputClick()
        #endif
        terminalView?.send (data)
    }

    func clickAndInsertText (_ text: String)
    {
        #if os(iOS)
        UIDevice.current.playInputClick()
        #endif
        terminalView?.insertTextFromAccessory(text)
    }
    
    @objc func esc (_ sender: AnyObject) { clickAndSend ([0x1b]) }
    @objc func tab (_ sender: AnyObject) { clickAndSend ([0x9]) }
    @objc func enter (_ sender: AnyObject) { clickAndInsertText ("\n") }
    @objc func tilde (_ sender: AnyObject) { clickAndInsertText ("~") }
    @objc func pipe (_ sender: AnyObject) { clickAndInsertText ("|") }
    @objc func slash (_ sender: AnyObject) { clickAndInsertText ("/") }
    @objc func dash (_ sender: AnyObject) { clickAndInsertText ("-") }
    @objc func f1 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[0]) }
    @objc func f2 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[1]) }
    @objc func f3 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[2]) }
    @objc func f4 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[3]) }
    @objc func f5 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[4]) }
    @objc func f6 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[5]) }
    @objc func f7 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[6]) }
    @objc func f8 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[7]) }
    @objc func f9 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[8]) }
    @objc func f10 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[9]) }
    
    @objc
    func ctrl (_ sender: UIButton)
    {
        controlModifier.toggle()
    }

    // Controls the timer for auto-repeat
    var repeatCommand: (() -> ())? = nil
    var repeatTimer: Timer?
    var repeatTask: Task<(), Never>?
    
    func startTimerForKeypress (repeatKey: @escaping () -> ())
    {
        repeatKey ()
        repeatCommand = repeatKey
        
        repeatTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !(repeatTask?.isCancelled ?? true) else { return }
            let rc = self.repeatCommand
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                rc? ()
            }
        }
    }
    
    @objc
    func cancelTimer ()
    {
        repeatTimer?.invalidate()
        repeatCommand = nil
        repeatTimer = nil
        repeatTask?.cancel()
    }
    
    @objc func up (_ sender: UIButton)
    {
        startTimerForKeypress { self.terminalView?.sendKeyUp () }
    }
    
    @objc func down (_ sender: UIButton)
    {
        startTimerForKeypress { self.terminalView?.sendKeyDown () }
    }
    
    @objc func left (_ sender: UIButton)
    {
        startTimerForKeypress { self.terminalView?.sendKeyLeft() }
    }
    
    @objc func right (_ sender: UIButton)
    {
        startTimerForKeypress { self.terminalView?.sendKeyRight() }
    }


    @objc func toggleInputKeyboard (_ sender: UIButton) {
        guard let tv = terminalView else { return }
        let wasResponder = tv.isFirstResponder
        if wasResponder { _ = tv.resignFirstResponder() }
        
        if tv.inputView == nil {
            #if os(visionOS)
            tv.inputView = KeyboardView (frame: CGRect (origin: CGPoint.zero,
                                                        size: CGSize (width: 300,
                                                                      height: 400)),
                                         terminalView: terminalView)
            #else
            tv.inputView = KeyboardView (frame: CGRect (origin: CGPoint.zero,
                                                        size: CGSize (width: UIScreen.main.bounds.width,
                                                                      height: max((UIScreen.main.bounds.height / 5),140))),
                                         terminalView: terminalView)
            #endif
        } else {
            tv.inputView = nil
        }
        if wasResponder { _ = tv.becomeFirstResponder() }

    }

    @objc func toggleTouch (_ sender: UIButton) {
        terminalView?.allowMouseReporting.toggle()
        touchButton.isSelected = !(terminalView?.allowMouseReporting ?? false)
    }

    var leftViews: [UIView] = []
    var floatViews: [UIView] = []
    var rightViews: [UIView] = []
    
    /**
     * This method setups the internal data structures to setup the UI shown on the accessory view,
     * if you provide your own implementation, you are responsible for adding all the elements to the
     * this view, and flagging some of the public properties declared here.
     */
    public func setupUI ()
    {
        for view in views {
            view.removeFromSuperview()
        }
        views = []
        leftViews = []
        rightViews = []
        floatViews = []
        terminalView?.setupKeyboardButtonColors ()
        self.controlButton = nil

        let enterButton = makeButton("enter", #selector(enter), isNormal: false)
        enterButton.sizeToFit()
        let minWidth: CGFloat = _useSmall ? 44 : 56
        if enterButton.frame.width < minWidth {
            enterButton.frame = CGRect(
                origin: CGPoint.zero,
                size: CGSize(width: minWidth, height: frame.height - 8)
            )
        }
        rightViews.append(enterButton)
        views.append(contentsOf: rightViews)
        

        for view in views {
            addSubview(view)
        }
        layoutSubviews ()
    }
    
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
return
        setupUI()
    }

    var _useSmall: Bool {
        get {
            frame.width < 380
        }
    }
    
    var buttonPad = 4.0
    public override func layoutSubviews() {
        var x: CGFloat = 2
        let dh = views.reduce (0) { max ($0, $1.frame.size.height )}
        
        for view in leftViews + floatViews {
            let size = view.frame.size
            view.frame = CGRect(x: x, y: 4, width: size.width, height: dh)
            x += size.width + buttonPad
        }
        
        var right = frame.width - 2
        for view in rightViews.reversed() {
            let size = view.frame.size
            view.frame = CGRect (x: right-size.width, y: 4, width: size.width, height: dh)
            right -= size.width + buttonPad
        }
    }
    
    func makeAutoRepeatButton (_ iconName: String, _ action: Selector) -> UIButton
    {
        let b = makeButton ("", action, icon: iconName)
        b.addTarget(self, action: #selector(cancelTimer), for: .touchUpOutside)
        b.addTarget(self, action: #selector(cancelTimer), for: .touchCancel)
        b.addTarget(self, action: #selector(cancelTimer), for: .touchUpInside)
        return b
    }
    
    func makeButton (_ title: String, _ action: Selector, icon: String = "", isNormal: Bool = true) -> UIButton
    {
        let useSmall = self._useSmall
        let b = BackgroundSelectedButton.init(type: .roundedRect)
        
        TerminalAccessory.styleButton (b)
        b.addTarget(self, action: action, for: .touchDown)
        b.setTitle(title, for: .normal)
        guard let terminalView else {
            return b
        }
        b.color = isNormal ? terminalView.buttonBackgroundColor : terminalView.buttonDarkBackgroundColor
        b.setTitleColor(terminalView.buttonColor, for: .normal)
        b.setTitleColor(terminalView.buttonColor, for: .selected)
        if useSmall {
            b.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        }
        b.backgroundColor = isNormal ? terminalView.buttonBackgroundColor : terminalView.buttonDarkBackgroundColor
        
        if icon != "" {
            if let img = UIImage (systemName: icon, withConfiguration: UIImage.SymbolConfiguration (pointSize: 14.0)) {
                b.setImage(img.withTintColor(terminalView.buttonColor, renderingMode: .alwaysOriginal), for: .normal)
            }
        }
        return b
    }
    
    func makeDouble (_ primary: String, _ secondary: String) -> UIView {
        let b = DoubleButton (frame: CGRect (x: 0, y: 0, width: 20, height: 26))
        b.primaryText = primary
        b.secondaryText = secondary
        return b
    }
    
    // I am not committed to this style, this is just something quick to get going
    static func styleButton (_ b: UIButton)
    {
        b.layer.cornerRadius = 5
        b.layer.masksToBounds = true
        b.layer.shadowOffset = CGSize(width: 0, height: 1.0)
        b.layer.shadowRadius = 0.0
        b.layer.shadowOpacity = 0.35
    }
}


class BackgroundSelectedButton: UIButton {
    
    var color: UIColor?
    
    override var isSelected: Bool {
        didSet {
            self.backgroundColor = isSelected ? UIView().tintColor : color
        }
    }
}
#endif
