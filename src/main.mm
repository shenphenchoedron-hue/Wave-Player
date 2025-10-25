#import <Cocoa/Cocoa.h>
#import "SamplePlayer.h"

static const NSInteger kFirstMidiNote = 21;  // A0
static const NSInteger kLastMidiNote = 108;  // C8
static const NSInteger kWhiteKeyCount = 52;

@class KeyboardView;

@protocol KeyboardViewDelegate <NSObject>
- (void)keyboardView:(KeyboardView *)view didPressMIDINote:(NSInteger)midiNote;
- (void)keyboardView:(KeyboardView *)view didReleaseMIDINote:(NSInteger)midiNote;
@end

@interface KeyboardKey : NSObject
@property (nonatomic, assign) NSInteger midiNote;
@property (nonatomic, assign) BOOL black;
@property (nonatomic, assign) NSRect frame;
@end

@implementation KeyboardKey
@end

@interface KeyboardView : NSView
@property (nonatomic, weak) id<KeyboardViewDelegate> delegate;
@end

@implementation KeyboardView {
    NSMutableArray<KeyboardKey *> *_keys;
    NSMutableSet<NSNumber *> *_pressed;
    NSInteger _activeMidiNote;
    BOOL _trackingMouse;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _keys = [NSMutableArray array];
        _pressed = [NSMutableSet set];
        _activeMidiNote = NSNotFound;
        [self updateKeyLayout];
        [self setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    }
    return self;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self updateKeyLayout];
    [self setNeedsDisplay:YES];
}

- (void)updateKeyLayout {
    [_keys removeAllObjects];

    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;
    if (width <= 0 || height <= 0) {
        return;
    }

    CGFloat whiteWidth = width / (CGFloat)kWhiteKeyCount;
    CGFloat whiteHeight = height;
    CGFloat blackHeight = height * 0.6f;
    CGFloat blackWidth = whiteWidth * 0.6f;

    NSInteger whiteIndex = 0;
    for (NSInteger midi = kFirstMidiNote; midi <= kLastMidiNote; ++midi) {
        NSInteger noteInOctave = (midi % 12);
        BOOL isBlack = (noteInOctave == 1 || noteInOctave == 3 || noteInOctave == 6 || noteInOctave == 8 || noteInOctave == 10);
        if (!isBlack) {
            CGFloat x = whiteIndex * whiteWidth;
            KeyboardKey *key = [[KeyboardKey alloc] init];
            key.midiNote = midi;
            key.black = NO;
            key.frame = NSMakeRect(x, 0, whiteWidth, whiteHeight);
            [_keys addObject:key];
            whiteIndex += 1;
        }
    }

    NSMutableArray<KeyboardKey *> *blackKeys = [NSMutableArray array];
    for (NSInteger midi = kFirstMidiNote; midi <= kLastMidiNote; ++midi) {
        NSInteger noteInOctave = (midi % 12);
        BOOL isBlack = (noteInOctave == 1 || noteInOctave == 3 || noteInOctave == 6 || noteInOctave == 8 || noteInOctave == 10);
        if (isBlack) {
            NSInteger precedingWhiteIndex = [self precedingWhiteIndexForMidi:midi];
            if (precedingWhiteIndex < 0 || precedingWhiteIndex >= _keys.count) {
                continue;
            }
            KeyboardKey *precedingWhite = _keys[precedingWhiteIndex];
            CGFloat originX = precedingWhite.frame.origin.x + precedingWhite.frame.size.width - (blackWidth * 0.5f);
            originX = MAX(originX, 0.0f);
            originX = MIN(originX, width - blackWidth);
            KeyboardKey *key = [[KeyboardKey alloc] init];
            key.midiNote = midi;
            key.black = YES;
            key.frame = NSMakeRect(originX, whiteHeight - blackHeight, blackWidth, blackHeight);
            [blackKeys addObject:key];
        }
    }

    [_keys addObjectsFromArray:blackKeys];
}

- (NSInteger)precedingWhiteIndexForMidi:(NSInteger)midi {
    NSInteger count = 0;
    for (NSInteger note = kFirstMidiNote; note <= midi; ++note) {
        NSInteger noteInOctave = (note % 12);
        BOOL isBlack = (noteInOctave == 1 || noteInOctave == 3 || noteInOctave == 6 || noteInOctave == 8 || noteInOctave == 10);
        if (!isBlack) {
            if (note == midi) {
                return count;
            }
            count += 1;
        } else if (note == midi) {
            return count - 1;
        }
    }
    return -1;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    [[NSColor darkGrayColor] setFill];
    NSRectFill(self.bounds);

    NSMutableArray<KeyboardKey *> *whiteKeys = [NSMutableArray array];
    NSMutableArray<KeyboardKey *> *blackKeys = [NSMutableArray array];
    for (KeyboardKey *key in _keys) {
        if (key.black) {
            [blackKeys addObject:key];
        } else {
            [whiteKeys addObject:key];
        }
    }

    for (KeyboardKey *key in whiteKeys) {
        NSBezierPath *path = [NSBezierPath bezierPathWithRect:key.frame];
        if ([_pressed containsObject:@(key.midiNote)]) {
            [[NSColor colorWithCalibratedRed:0.8 green:0.85 blue:1.0 alpha:1.0] setFill];
        } else {
            [[NSColor whiteColor] setFill];
        }
        [path fill];
        [[NSColor blackColor] setStroke];
        [path stroke];
    }

    for (KeyboardKey *key in blackKeys) {
        NSBezierPath *path = [NSBezierPath bezierPathWithRect:key.frame];
        if ([_pressed containsObject:@(key.midiNote)]) {
            [[NSColor colorWithCalibratedWhite:0.2 alpha:1.0] setFill];
        } else {
            [[NSColor blackColor] setFill];
        }
        [path fill];
    }
}

- (void)mouseDown:(NSEvent *)event {
    _trackingMouse = YES;
    [self updateActiveNoteForEvent:event];
}

- (void)mouseDragged:(NSEvent *)event {
    if (_trackingMouse) {
        [self updateActiveNoteForEvent:event];
    }
}

- (void)mouseUp:(NSEvent *)event {
    if (_trackingMouse) {
        if (_activeMidiNote != NSNotFound) {
            [self releaseNote:_activeMidiNote];
        }
        _trackingMouse = NO;
        _activeMidiNote = NSNotFound;
    }
}

- (void)updateActiveNoteForEvent:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger midiNote = [self midiNoteAtPoint:point];
    if (midiNote == NSNotFound) {
        if (_activeMidiNote != NSNotFound) {
            [self releaseNote:_activeMidiNote];
            _activeMidiNote = NSNotFound;
        }
        return;
    }

    if (_activeMidiNote != midiNote) {
        if (_activeMidiNote != NSNotFound) {
            [self releaseNote:_activeMidiNote];
        }
        _activeMidiNote = midiNote;
        [self pressNote:midiNote];
    }
}

- (NSInteger)midiNoteAtPoint:(NSPoint)point {
    for (KeyboardKey *key in _keys) {
        if (key.black && NSPointInRect(point, key.frame)) {
            return key.midiNote;
        }
    }
    for (KeyboardKey *key in _keys) {
        if (!key.black && NSPointInRect(point, key.frame)) {
            return key.midiNote;
        }
    }
    return NSNotFound;
}

- (void)pressNote:(NSInteger)midiNote {
    [_pressed addObject:@(midiNote)];
    [self setNeedsDisplay:YES];
    if ([self.delegate respondsToSelector:@selector(keyboardView:didPressMIDINote:)]) {
        [self.delegate keyboardView:self didPressMIDINote:midiNote];
    }
}

- (void)releaseNote:(NSInteger)midiNote {
    [_pressed removeObject:@(midiNote)];
    [self setNeedsDisplay:YES];
    if ([self.delegate respondsToSelector:@selector(keyboardView:didReleaseMIDINote:)]) {
        [self.delegate keyboardView:self didReleaseMIDINote:midiNote];
    }
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate, KeyboardViewDelegate>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) KeyboardView *keyboardView;
@property (nonatomic, strong) SamplePlayer *player;
@property (nonatomic, strong) NSTextField *statusLabel;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSRect frame = NSMakeRect(0, 0, 960, 360);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:(NSWindowStyleMaskTitled |
                                                         NSWindowStyleMaskClosable |
                                                         NSWindowStyleMaskMiniaturizable |
                                                         NSWindowStyleMaskResizable)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    [self.window center];
    [self.window setTitle:@"Wave Keyboard Player"];

    NSView *contentView = self.window.contentView;

    NSButton *loadButton = [NSButton buttonWithTitle:@"Load Sample"
                                              target:self
                                              action:@selector(loadSample:)];
    loadButton.bezelStyle = NSBezelStyleRounded;
    loadButton.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:loadButton];

    self.statusLabel = [[NSTextField alloc] init];
    self.statusLabel.editable = NO;
    self.statusLabel.bezeled = NO;
    self.statusLabel.drawsBackground = NO;
    self.statusLabel.stringValue = @"No sample loaded";
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:self.statusLabel];

    self.keyboardView = [[KeyboardView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height - 80)];
    self.keyboardView.delegate = self;
    self.keyboardView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:self.keyboardView];

    NSDictionary<NSString *, id> *views = @{ @"loadButton": loadButton,
                                             @"statusLabel": self.statusLabel,
                                             @"keyboardView": self.keyboardView };
    [contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-20-[loadButton(120)]-20-[statusLabel]-20-|"
                                                                        options:NSLayoutFormatAlignAllCenterY
                                                                        metrics:nil
                                                                          views:views]];
    [contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-20-[loadButton]-20-[keyboardView]-20-|"
                                                                        options:0
                                                                        metrics:nil
                                                                          views:views]];
    [contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-20-[keyboardView]-20-|"
                                                                        options:0
                                                                        metrics:nil
                                                                          views:views]];

    self.player = [[SamplePlayer alloc] init];

    [self.window makeKeyAndOrderFront:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)loadSample:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedFileTypes = @[ @"wav", @"WAV" ];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSURL *url = panel.URL;
            NSError *error = nil;
            if ([self.player loadSampleAtURL:url error:&error]) {
                self.statusLabel.stringValue = [NSString stringWithFormat:@"Loaded: %@", url.lastPathComponent ?: @"sample"];
            } else {
                self.statusLabel.stringValue = error.localizedDescription ?: @"Failed to load sample";
            }
        }
    }];
}

#pragma mark - KeyboardViewDelegate

- (void)keyboardView:(KeyboardView *)view didPressMIDINote:(NSInteger)midiNote {
    if (![self.player hasLoadedSample]) {
        self.statusLabel.stringValue = @"Load a WAV sample to begin";
        return;
    }
    [self.player playMIDINote:midiNote];
}

- (void)keyboardView:(KeyboardView *)view didReleaseMIDINote:(NSInteger)midiNote {
    [self.player stopMIDINote:midiNote];
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}
