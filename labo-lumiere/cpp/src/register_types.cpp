// Enregistre la classe ArbreLumiere auprès de Godot.
#include "arbre_lumiere.h"
#include "trou_de_ver.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

static void initialiser(ModuleInitializationLevel p_niveau) {
	if (p_niveau != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(ArbreLumiere);
	GDREGISTER_CLASS(TrouDeVer);   // Einstein C
}

static void terminer(ModuleInitializationLevel p_niveau) {}

extern "C" {
GDExtensionBool GDE_EXPORT lumiere_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialiser);
	init_obj.register_terminator(terminer);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
