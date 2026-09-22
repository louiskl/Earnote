#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Führt `block` aus und macht aus einer Objective-C-Ausnahme einen Fehler.
///
/// AVFoundation meldet Audiofehler als `NSException`. Swift kann die nicht fangen: Jede davon
/// beendet die App sofort (`abort()`), egal wie viel `do`/`catch` darum steht. Genau daran ist
/// Earnote am 22.09.2026 dreimal gestorben – beim Mikrofontest, beim Aufnahmestart und beim
/// Gerätewechsel im Call. Hier wird daraus ein normaler Fehler, den die Aufnahme abfangen kann.
BOOL EarnoteCatchException(void (NS_NOESCAPE ^block)(void), NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END
