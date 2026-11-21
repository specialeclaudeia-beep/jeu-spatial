// Enregistre les classes C++ auprès de Godot : lumière (ArbreLumiere, TrouDeVer) et son (SyntheSon, phase 2).
#include "arbre_lumiere.h"
#include "chocs_son.h"
#include "synthe_son.h"
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
	GDREGISTER_CLASS(SyntheSon);   // son, phase 2 : sons continus fabriqués en direct
	GDREGISTER_INTERNAL_CLASS(LectureSyntheSon);
	GDREGISTER_CLASS(ChocsSon);    // son, phase 3 : sons brefs fabriqués en direct
	GDREGISTER_INTERNAL_CLASS(LectureChocsSon);
	GDREGISTER_CLASS(AnalyseSon);  // son : outil des tests
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
