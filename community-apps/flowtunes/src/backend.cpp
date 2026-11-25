#include "backend.h"

Backend::Backend(const Places &places, QObject *parent)
    : QObject(parent),
      m_models(places.engineState, places.engineKey, places.engineCommand, places.meminfo),
      m_flow(&m_models, places.musicFolder),
      m_mpris(&m_flow) {}
