#include <QAction>
#include <QCoreApplication>
#include <QMenu>
#include <QString>
#include <QWidget>

#include <cstdlib>
#include <dlfcn.h>

#include "dlhook.h"
#include "menu.h"
#include "util.h"

typedef QWidget MenuTextItem; // it's actually a subclass, but we don't need it's functionality directly, so we'll stay on the safe side

// AbstractNickelMenuController::createMenuTextItem creates a menu item in the
// given QMenu with the specified label. The first bool parameter adds space to
// the left of the item for a checkbox, and the second bool checks it (see the
// search menu for an example of this being used). IDK what the last parameter
// is for, but I suspect it might be passed to QObject::setObjectName (I haven't
// tested it directly, and it's been empty in the menus I've tried so far).
static MenuTextItem* (*AbstractNickelMenuController_createMenuTextItem_orig)(void*, QMenu*, QString const&, bool, bool, QString const&) = NULL;
static MenuTextItem* (*AbstractNickelMenuController_createMenuTextItem)(void*, QMenu*, QString const&, bool, bool, QString const&);

// AbstractNickelMenuController::createAction finishes adding the action to the
// menu. IDK what the bool params are for, but the first and second always seem
// to be true (I know one or the other is for if it is greyed out), and the
// third is whether to add a separator after it.
static QAction* (*AbstractNickelMenuController_createAction)(void*, QMenu*, QWidget*, bool, bool, bool);

// ConfirmationDialogFactory::showOKDialog does what it says, with the provided
// title and body text. Note that it should be called from the GUI thread (or
// a signal handler).
static void (*ConfirmationDialogFactory_showOKDialog)(QString const&, QString const&);

static nm_menu_item_t **_items;
static size_t _items_n;

extern "C" int nm_menu_hook(void *libnickel, nm_menu_item_t **items, size_t items_n, char **err_out) {
    #define NM_ERR_RET 1
    reinterpret_cast<void*&>(AbstractNickelMenuController_createMenuTextItem) = dlsym(libnickel, "_ZN28AbstractNickelMenuController18createMenuTextItemEP5QMenuRK7QStringbbS4_");
    reinterpret_cast<void*&>(AbstractNickelMenuController_createAction) = dlsym(libnickel, "_ZN22AbstractMenuController12createActionEP5QMenuP7QWidgetbbb");
    reinterpret_cast<void*&>(ConfirmationDialogFactory_showOKDialog) = dlsym(libnickel, "_ZN25ConfirmationDialogFactory12showOKDialogERK7QStringS2_");

    NM_ASSERT(AbstractNickelMenuController_createMenuTextItem, "unsupported firmware: could not find AbstractNickelMenuController::createMenuTextItem(void* _this, QMenu*, QString, bool, bool, QString const&)");
    NM_ASSERT(AbstractNickelMenuController_createAction, "unsupported firmware: could not find AbstractNickelMenuController::createAction(void* _this, QMenu*, QWidget*, bool, bool, bool)");
    NM_ASSERT(AbstractNickelMenuController_createAction, "unsupported firmware: could not find ConfirmationDialogFactory::showOKDialog(QString const&, QString const&)");

    void* nmh = dlsym(RTLD_DEFAULT, "_nm_menu_hook");
    NM_ASSERT(nmh, "internal error: could not dlsym _nm_menu_hook");

    char *err;
    reinterpret_cast<void*&>(AbstractNickelMenuController_createMenuTextItem_orig) = nm_dlhook(libnickel, "_ZN28AbstractNickelMenuController18createMenuTextItemEP5QMenuRK7QStringbbS4_", nmh, &err);
    NM_ASSERT(AbstractNickelMenuController_createMenuTextItem_orig, "failed to hook _ZN28AbstractNickelMenuController18createMenuTextItemEP5QMenuRK7QStringbbS4_: %s", err);

    _items = items;
    _items_n = items_n;

    NM_RETURN_OK(0);
    #undef NM_ERR_RET
}

extern "C" MenuTextItem* _nm_menu_hook(void* _this, QMenu* menu, QString const& label, bool checkable, bool checked, QString const& thingy) {
    NM_LOG("AbstractNickelMenuController::createMenuTextItem(%p, `%s`, %d, %d, `%s`)", menu, qPrintable(label), checkable, checked, qPrintable(thingy));

    QString trmm = QCoreApplication::translate("StatusBarMenuController", "Help");
    QString trrm = QCoreApplication::translate("DictionaryActionProxy", "Dictionary");
    NM_LOG("Comparing against '%s', '%s'", qPrintable(trmm), qPrintable(trrm));

    bool ismm, isrm;
    if ((ismm = (label == trmm) && !checkable))
        NM_LOG("Intercepting main menu (label=Help, checkable=false)...");
    if ((isrm = (label == trrm) && !checkable))
        NM_LOG("Intercepting reader menu (label=Dictionary, checkable=false)...");

    for (size_t i = 0; i < _items_n; i++) {
        nm_menu_item_t *it = _items[i];
        if (it->loc == NM_MENU_LOCATION_MAIN_MENU && !ismm)
            continue;
        if (it->loc == NM_MENU_LOCATION_READER_MENU && !isrm)
            continue;

        NM_LOG("Adding item '%s'...", it->lbl);

        MenuTextItem* item = AbstractNickelMenuController_createMenuTextItem_orig(_this, menu, QString::fromUtf8(it->lbl), false, false, "");
        QAction* action = AbstractNickelMenuController_createAction(_this, menu, item, true, true, true);

        // note: we're capturing by value, i.e. the pointer to the global variable, rather then the stack variable, so this is safe
        QObject::connect(action, &QAction::triggered, std::function<void(bool)>([it](bool){
            NM_LOG("Item '%s' pressed...", it->lbl);
            char *err;
            for (nm_menu_action_t *cur = it->action; cur; cur = cur->next) {
                if (cur->act(cur->arg, &err) && err) {
                    NM_LOG("Got error: '%s', displaying...", err);
                    ConfirmationDialogFactory_showOKDialog(QString::fromUtf8(it->lbl), QString::fromUtf8(err));
                    free(err);
                    return;
                }
            }
            NM_LOG("Success!");
        }));
    }

    return AbstractNickelMenuController_createMenuTextItem_orig(_this, menu, label, checkable, checked, thingy);
}
