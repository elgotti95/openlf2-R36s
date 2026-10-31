#ifndef MERCENARIES_PLUGIN_HOST_H
#define MERCENARIES_PLUGIN_HOST_H
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
int merc_plugins_initialize(void *guest_base, size_t guest_bytes);
int merc_plugins_update(void);
void merc_plugins_shutdown(void);
const char *merc_plugins_error(void);
void merc_plugins_show_error(void);
#ifdef __cplusplus
}
#endif
#endif

