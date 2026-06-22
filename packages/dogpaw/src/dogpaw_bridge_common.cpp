#include "dogpaw_bridge.h"

// Define VERBOSITY to 0 to silence logging if headers depend on it
#ifndef VERBOSITY
#define VERBOSITY 0
#endif

#include "DPQueue.hpp"
#include "MidiMessage.hpp"
#include "dataTypes/DppParamQueueMsg.hpp"
#include "dataTypes/NoteControlMsg.hpp"
#include "dataTypes/OutputValue.hpp"
#include "sharedData/ScopeBuffer.hpp"
#include "dataTypes/VoiceMessage.hpp"
#include "logging/AppLogger.hpp"
#include "sharedData/KeyPosBuffer.hpp"
#include "sharedData/SharedData.hpp"
#include <algorithm>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <sstream>
#include <string>
#include <tuple>

// Process management and server detection
#include <fcntl.h>
#include <signal.h>
#include <sys/file.h>
#include <sys/prctl.h>
#include <sys/wait.h>
#include <unistd.h>
#include <cerrno>

using namespace DPCommon;
using std::pair;
using std::string;
using std::tuple;

//=============================================================================
// Internal Helpers
//=============================================================================

// Helper to calculate data size (replicated from EndpointData.cpp)
size_t calculate_data_size(int data_type_idx) {
  switch (data_type_idx) {
  case DPPB_TYPE_FLOAT:
    return sizeof(float);
  case DPPB_TYPE_FLOAT2:
    return sizeof(float) * 2;
  case DPPB_TYPE_FLOAT3:
    return sizeof(float) * 3;
  case DPPB_TYPE_FLOAT4:
    return sizeof(float) * 4;
  case DPPB_TYPE_INT:
    return sizeof(int);
  case DPPB_TYPE_INT2:
    return sizeof(int) * 2;
  case DPPB_TYPE_TOGGLE:
  case DPPB_TYPE_MOMENTARY:
    return sizeof(bool);
  case DPPB_TYPE_ENUM:
    return sizeof(int);
  case DPPB_TYPE_COLOR:
    return sizeof(uint32_t);
  case DPPB_TYPE_NOTE_CONTROL:
    return sizeof(NoteCtrlMsg);
  case DPPB_TYPE_MIDI_MESSAGE:
    return sizeof(MidiMsg);
  case DPPB_TYPE_LED_MESSAGE:
    return sizeof(LEDMsg);
  case DPPB_TYPE_KEY_POSITION:
    return sizeof(PosTriple);
  case DPPB_TYPE_NEAR_PRESS:
    return sizeof(NearPressPositionData);
  case DPPB_TYPE_RAW_SENSORS:
    return sizeof(pair<uint16_t, uint16_t>);
  case DPPB_TYPE_VOICE_MESSAGE:
    return sizeof(VoiceMessage);
  case DPPB_TYPE_VOICE_OUTPUT_VALUE:
    return sizeof(VoiceOutputValue);
  case DPPB_TYPE_GLOBAL_OUTPUT_VALUE:
    return sizeof(GlobalOutputValue);
  case DPPB_TYPE_KEY_PRESS:
    return sizeof(KeyMsg);
  case DPPB_TYPE_DPP_EDITOR_MESSAGE:
    return sizeof(DppEditorMessage);
  case DPPB_TYPE_SCOPE_BUFFER:
    return sizeof(ScopeBufferPayload);
  default:
    return 0;
  }
}

// Helper to account for indexing with actual dimensions
size_t apply_indexing(size_t base_size, int index_type_idx, int dim1, int dim2) {
  if (base_size == 0)
    return 0;
  switch (index_type_idx) {
  case DPPB_INDEX_KEY:
    return base_size * (dim1 * dim2);
  case DPPB_INDEX_VOICE:
    return base_size * dim1;
  default:
    return base_size;
  }
}

// Type safety wrapper to distinguish different handle types at runtime
struct HandleHeader {
  int type;
  void *impl;
};

extern "C" {

/**
 * @brief Create a SharedData writer with instance-scoped namespace prefix
 * @param name Logical SharedData name (from Epiphany server)
 * @param size Buffer size in bytes
 * @param namespace_prefix Instance namespace prefix (e.g., "ep_default_"), empty string for legacy
 * @return Handle pointer, or nullptr on failure
 */
void *dppb_shared_writer_create(const char *name, int size, const char *namespace_prefix) {
  try {
    string nsPrefix = (namespace_prefix != nullptr) ? namespace_prefix : "";
    auto writer = new SharedDataWriter(name, size, nullptr, false, nsPrefix);
    auto handle = new HandleHeader{1, writer};
    return handle;
  } catch (...) {
    return nullptr;
  }
}

/**
 * @brief Create a SharedData reader with instance-scoped namespace prefix
 * @param name Logical SharedData name (from Epiphany server)
 * @param namespace_prefix Instance namespace prefix (e.g., "ep_default_"), empty string for legacy
 * @return Handle pointer, or nullptr on failure
 */
void *dppb_shared_reader_create(const char *name, const char *namespace_prefix) {
  try {
    string nsPrefix = (namespace_prefix != nullptr) ? namespace_prefix : "";
    auto reader = new SharedDataReader(name, 0, nullptr, false, nsPrefix);
    auto handle = new HandleHeader{2, reader};
    return handle;
  } catch (...) {
    return nullptr;
  }
}

bool dppb_shared_write(void *handle, const void *data, int size) {
  if (!handle)
    return false;
  auto header = static_cast<HandleHeader *>(handle);
  if (header->type != 1)
    return false;

  auto writer = static_cast<SharedDataWriter *>(header->impl);
  try {
    auto sharedObject = writer->reserveWriteBuffer();
    if (sharedObject.bufferPtr == nullptr)
      return false;
    if ((size_t)size != sharedObject.bufferSize) {
      AppLogger::warning("dppb_shared_write: Data size mismatch! size=" + std::to_string(size) +
                         ", bufferSize=" + std::to_string(sharedObject.bufferSize));
    }
    std::memcpy(sharedObject.bufferPtr, data, sharedObject.bufferSize);
    writer->releaseWriteBuffer();
    return true;
  } catch (...) {
    return false;
  }
}

bool dppb_shared_read(void *handle, void *out_data, int size) {
  if (!handle)
    return false;
  auto header = static_cast<HandleHeader *>(handle);
  if (header->type != 2)
    return false;

  auto reader = static_cast<SharedDataReader *>(header->impl);
  try {
    auto sharedObject = reader->reserveReadBuffer();
    if (sharedObject.bufferPtr == nullptr)
      return false;
    if ((size_t)size != sharedObject.bufferSize) {
      AppLogger::warning("dppb_shared_read: Data size mismatch! size=" + std::to_string(size) +
                         ", bufferSize=" + std::to_string(sharedObject.bufferSize));
    }
    size_t copySize = std::min((size_t)size, sharedObject.bufferSize);
    std::memcpy(out_data, sharedObject.bufferPtr, copySize);
    reader->releaseReadBuffer();
    return true;
  } catch (...) {
    return false;
  }
}

void dppb_shared_destroy(void *handle) {
  if (!handle)
    return;
  auto header = static_cast<HandleHeader *>(handle);
  if (header->type == 1) {
    delete static_cast<SharedDataWriter *>(header->impl);
  } else if (header->type == 2) {
    delete static_cast<SharedDataReader *>(header->impl);
  }
  delete header;
}

bool dppb_shared_writer_adjust_buffer_size(void *handle, int delta_buffer_size) {
  std::ostringstream ptrStream;
  ptrStream << "0x" << std::hex << reinterpret_cast<uintptr_t>(handle);
  AppLogger::debug("dppb_shared_writer_adjust_buffer_size: Received handle pointer: " + ptrStream.str() +
                   ", delta: " + std::to_string(delta_buffer_size));

  if (!handle) {
    AppLogger::error("dppb_shared_writer_adjust_buffer_size: Invalid handle (null)");
    return false;
  }

  auto header = static_cast<HandleHeader *>(handle);

  std::ostringstream implStream;
  implStream << "0x" << std::hex << reinterpret_cast<uintptr_t>(header->impl);
  AppLogger::debug("dppb_shared_writer_adjust_buffer_size: HandleHeader type: " + std::to_string(header->type) + ", impl ptr: " + implStream.str());

  if (header->type != 1) {
    AppLogger::error("dppb_shared_writer_adjust_buffer_size: Handle is not a writer, type is: " + std::to_string(header->type));
    return false;
  }

  auto writer = static_cast<SharedDataWriter *>(header->impl);
  try {
    AppLogger::debug("dppb_shared_writer_adjust_buffer_size: Calling adjustBufferSize on SharedDataWriter");
    writer->adjustBufferSize(delta_buffer_size);
    AppLogger::debug("dppb_shared_writer_adjust_buffer_size: Successfully adjusted buffer size");
    return true;
  } catch (const std::exception &e) {
    AppLogger::error("dppb_shared_writer_adjust_buffer_size: Failed to adjust buffer size: " + std::string(e.what()));
    return false;
  }
}

} // extern "C"

//=============================================================================
// MESSAGE QUEUE IMPLEMENTATION
//=============================================================================

template <typename T> IDogPawProducer *create_producer_impl(const string &qn, const string &sn, int index_type) {
  const string &queueName = qn;
  const string &socketName = sn;

  if (index_type == DPPB_INDEX_NONE) {
    return new DogPawProducer<T>(queueName.c_str(), socketName.c_str());
  } else if (index_type == DPPB_INDEX_KEY) {
    return new DogPawProducer<pair<pair<int, int>, T>>(queueName.c_str(), socketName.c_str());
  } else if (index_type == DPPB_INDEX_VOICE) {
    return new DogPawProducer<pair<int, T>>(queueName.c_str(), socketName.c_str());
  } else if (index_type == DPPB_INDEX_CUSTOM) {
    return new DogPawProducer<pair<string, T>>(queueName.c_str(), socketName.c_str());
  }
  return nullptr;
}

template <typename T> IDogPawConsumer *create_consumer_impl(const string &qn, const string &sn, int index_type) {
  const string &queueName = qn;
  const string &socketName = sn;

  if (index_type == DPPB_INDEX_NONE) {
    return new DogPawConsumer<T>(queueName.c_str(), socketName.c_str());
  } else if (index_type == DPPB_INDEX_KEY) {
    return new DogPawConsumer<pair<pair<int, int>, T>>(queueName.c_str(), socketName.c_str());
  } else if (index_type == DPPB_INDEX_VOICE) {
    return new DogPawConsumer<pair<int, T>>(queueName.c_str(), socketName.c_str());
  } else if (index_type == DPPB_INDEX_CUSTOM) {
    return new DogPawConsumer<pair<string, T>>(queueName.c_str(), socketName.c_str());
  }
  return nullptr;
}

extern "C" {

void *dppb_producer_create(const char *queue_name, const char *socket_name, int data_type_idx, int index_type_idx) {
  try {
    IDogPawProducer *impl = nullptr;
    string qn = queue_name;
    string sn = socket_name;

    switch (data_type_idx) {
    case DPPB_TYPE_FLOAT:
      impl = create_producer_impl<float>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_FLOAT2:
      impl = create_producer_impl<pair<float, float>>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_FLOAT3:
      impl = create_producer_impl<tuple<float, float, float>>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_FLOAT4:
      impl = create_producer_impl<tuple<float, float, float, float>>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_INT:
      impl = create_producer_impl<int32_t>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_INT2:
      impl = create_producer_impl<pair<int, int>>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_TOGGLE:
    case DPPB_TYPE_MOMENTARY:
      impl = create_producer_impl<bool>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_ENUM:
      impl = create_producer_impl<int>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_KEY_PRESS:
      impl = create_producer_impl<KeyMsg>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_NEAR_PRESS:
      impl = create_producer_impl<NearPressPositionData>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_RAW_SENSORS:
      impl = create_producer_impl<pair<uint16_t, uint16_t>>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_NOTE_CONTROL:
      impl = create_producer_impl<NoteCtrlMsg>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_MIDI_MESSAGE:
      impl = create_producer_impl<MidiMsg>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_LED_MESSAGE:
      impl = create_producer_impl<LEDMsg>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_KEY_POSITION:
      impl = create_producer_impl<PosTriple>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_VOICE_MESSAGE:
      impl = create_producer_impl<VoiceMessage>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_VOICE_OUTPUT_VALUE:
      impl = create_producer_impl<VoiceOutputValue>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_GLOBAL_OUTPUT_VALUE:
      impl = create_producer_impl<GlobalOutputValue>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_DPP_EDITOR_MESSAGE:
      impl = create_producer_impl<DppEditorMessage>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_SCOPE_BUFFER:
      impl = create_producer_impl<ScopeBufferPayload>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_CUSTOM:
      impl = create_producer_impl<string>(qn, sn, index_type_idx);
      break;
    }

    if (impl) {
      return new HandleHeader{3, impl};
    }
  } catch (...) {
  }
  return nullptr;
}

int dppb_producer_enqueue(void *handle, const void *data) {
  if (!handle) {
    AppLogger::error("dppb_producer_enqueue: Invalid handle (null)");
    return -3;
  }
  auto header = static_cast<HandleHeader *>(handle);
  if (header->type != 3) {
    AppLogger::error("dppb_producer_enqueue: Invalid handle type: " + std::to_string(header->type));
    return -3;
  }

  auto producer = static_cast<IDogPawProducer *>(header->impl);
  try {
    int result = producer->enqueue(data);
    return result;
  } catch (const std::exception &e) {
    AppLogger::error("dppb_producer_enqueue: Exception: " + std::string(e.what()));
    return -3;
  } catch (...) {
    AppLogger::error("dppb_producer_enqueue: Unknown exception");
    return -3;
  }
}

void *dppb_consumer_create(const char *queue_name, const char *socket_name, int data_type_idx, int index_type_idx) {
  try {
    if (VERBOSITY > 0)
      std::cout << "DEBUG: C++ dppb_consumer_create q=" << queue_name << " s=" << socket_name << std::endl;
    IDogPawConsumer *impl = nullptr;
    string qn = queue_name;
    string sn = socket_name;

    switch (data_type_idx) {
    case DPPB_TYPE_FLOAT:
      impl = create_consumer_impl<float>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_FLOAT2:
      impl = create_consumer_impl<pair<float, float>>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_FLOAT3:
      impl = create_consumer_impl<tuple<float, float, float>>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_FLOAT4:
      impl = create_consumer_impl<tuple<float, float, float, float>>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_INT:
      impl = create_consumer_impl<int32_t>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_INT2:
      impl = create_consumer_impl<pair<int, int>>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_TOGGLE:
    case DPPB_TYPE_MOMENTARY:
      impl = create_consumer_impl<bool>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_ENUM:
      impl = create_consumer_impl<int>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_KEY_PRESS:
      impl = create_consumer_impl<KeyMsg>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_NEAR_PRESS:
      impl = create_consumer_impl<NearPressPositionData>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_RAW_SENSORS:
      impl = create_consumer_impl<pair<uint16_t, uint16_t>>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_NOTE_CONTROL:
      impl = create_consumer_impl<NoteCtrlMsg>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_MIDI_MESSAGE:
      impl = create_consumer_impl<MidiMsg>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_LED_MESSAGE:
      impl = create_consumer_impl<LEDMsg>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_KEY_POSITION:
      impl = create_consumer_impl<PosTriple>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_VOICE_MESSAGE:
      impl = create_consumer_impl<VoiceMessage>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_VOICE_OUTPUT_VALUE:
      impl = create_consumer_impl<VoiceOutputValue>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_GLOBAL_OUTPUT_VALUE:
      impl = create_consumer_impl<GlobalOutputValue>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_DPP_EDITOR_MESSAGE:
      impl = create_consumer_impl<DppEditorMessage>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_SCOPE_BUFFER:
      impl = create_consumer_impl<ScopeBufferPayload>(qn, sn, index_type_idx);
      break;
    case DPPB_TYPE_CUSTOM:
      impl = create_consumer_impl<string>(qn, sn, index_type_idx);
      break;
    }

    if (impl) {
      return new HandleHeader{4, impl};
    }
  } catch (...) {
  }
  return nullptr;
}

int dppb_consumer_poll(void *handle, void *out_buffer, int max_size) {
  if (!handle) {
    if (VERBOSITY > 0)
      std::cout << "DEBUG: C++ dppb_consumer_poll - handle is null" << std::endl;
    return 0;
  }
  auto header = static_cast<HandleHeader *>(handle);
  if (header->type != 4) {
    if (VERBOSITY > 0)
      std::cout << "DEBUG: C++ dppb_consumer_poll - invalid handle type: " << header->type << std::endl;
    return 0;
  }

  auto consumer = static_cast<IDogPawConsumer *>(header->impl);
  int bytesRead = 0;

  try {
    if (VERBOSITY > 0)
      std::cout << "DEBUG: C++ dppb_consumer_poll - calling pollOnce..." << std::endl;
    consumer->pollOnce([&](const void *data) {
      std::memcpy(out_buffer, data, max_size);
      bytesRead = max_size;
      if (VERBOSITY > 0)
        std::cout << "DEBUG: C++ poll got data, bytesRead=" << bytesRead << std::endl;
    });
    if (VERBOSITY > 0)
      std::cout << "DEBUG: C++ dppb_consumer_poll - pollOnce returned, bytesRead=" << bytesRead << std::endl;
  } catch (...) {
    if (VERBOSITY > 0)
      std::cout << "DEBUG: C++ poll exception" << std::endl;
  }

  return bytesRead;
}

void dppb_endpoint_destroy(void *handle) {
  if (!handle)
    return;
  auto header = static_cast<HandleHeader *>(handle);
  if (header->type == 3) {
    delete static_cast<IDogPawProducer *>(header->impl);
  } else if (header->type == 4) {
    delete static_cast<IDogPawConsumer *>(header->impl);
  }
  delete header;
}

int dppb_get_data_size(int data_type_idx, int index_type_idx, int index_dim1, int index_dim2) {
  size_t base = calculate_data_size(data_type_idx);
  return (int)apply_indexing(base, index_type_idx, index_dim1, index_dim2);
}

/**
 * @brief Check if Epiphany server is running by testing flock on port file
 */
int dppb_check_server_running(const char *port_file_path) {
  int fd = open(port_file_path, O_RDONLY);
  if (fd < 0) {
    return -1;
  }

  int ret = flock(fd, LOCK_SH | LOCK_NB);
  if (ret == 0) {
    flock(fd, LOCK_UN);
    close(fd);
    return 0;
  }

  int saved_errno = errno;

  if (saved_errno != EWOULDBLOCK) {
    AppLogger::error("dppb_check_server_running: Unexpected flock error: " + string(strerror(saved_errno)));
    close(fd);
    return -2;
  }

  char buffer[32];
  lseek(fd, 0, SEEK_SET);
  ssize_t bytesRead = read(fd, buffer, sizeof(buffer) - 1);
  close(fd);

  if (bytesRead > 0) {
    buffer[bytesRead] = '\0';
    try {
      int port = std::stoi(buffer);
      if (port > 0 && port <= 65535) {
        return port;
      }
    } catch (...) {
      AppLogger::warning("dppb_check_server_running: Failed to parse port from file");
    }
  }

  return 0;
}

/**
 * @brief Wait for server to become ready (polls with flock check)
 */
int dppb_wait_for_server(const char *port_file_path, int timeout_ms) {
  int elapsed = 0;
  const int poll_interval_ms = 50;

  while (elapsed < timeout_ms) {
    int result = dppb_check_server_running(port_file_path);
    if (result > 0) {
      return result;
    }
    if (result == -2) {
      AppLogger::error("dppb_wait_for_server: Unexpected error from dppb_check_server_running");
      return -1;
    }

    usleep(poll_interval_ms * 1000);
    elapsed += poll_interval_ms;
  }

  AppLogger::debug("dppb_wait_for_server: Timeout waiting for server");
  return 0;
}

/**
 * @brief Spawn process with PR_SET_PDEATHSIG so it auto-terminates when parent dies
 */
int dppb_spawn_with_death_signal(const char *program, const char **argv, int death_signal, const char *log_path) {
  pid_t pid = fork();

  if (pid < 0) {
    AppLogger::error("dppb_spawn_with_death_signal: fork() failed: " + string(strerror(errno)));
    return -1;
  }

  if (pid == 0) {
    prctl(PR_SET_PDEATHSIG, death_signal);

    int devnull = open("/dev/null", O_RDONLY);
    if (devnull >= 0) {
      dup2(devnull, STDIN_FILENO);
      close(devnull);
    }

    if (log_path != nullptr) {
      string actualLogPath;
      if (strcmp(log_path, "auto") == 0) {
        actualLogPath = "/tmp/epiphany_test_" + std::to_string(getpid()) + ".log";
      } else {
        actualLogPath = log_path;
      }

      int logFd = open(actualLogPath.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
      if (logFd >= 0) {
        dup2(logFd, STDOUT_FILENO);
        dup2(logFd, STDERR_FILENO);
        close(logFd);
      }
    }

    execv(program, const_cast<char **>(argv));
    _exit(127);
  }

  return pid;
}

/**
 * @brief Send signal to process
 */
int dppb_kill_process(int pid, int signal_num) {
  if (kill(pid, signal_num) < 0) {
    if (errno != ESRCH) {
      AppLogger::error("dppb_kill_process: kill(" + std::to_string(pid) + ", " + std::to_string(signal_num) +
                       ") failed: " + string(strerror(errno)));
    }
    return -1;
  }
  return 0;
}

/**
 * @brief Wait for process to exit with timeout
 */
int dppb_wait_process(int pid, int timeout_ms) {
  int status;
  int elapsed = 0;
  const int poll_interval_ms = 50;

  while (elapsed < timeout_ms) {
    pid_t result = waitpid(pid, &status, WNOHANG);
    if (result > 0) {
      if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
      }
      if (WIFSIGNALED(status)) {
        return 128 + WTERMSIG(status);
      }
      return 0;
    }
    if (result < 0) {
      if (errno == ECHILD) {
        return 0;
      }
      AppLogger::error("dppb_wait_process: waitpid failed: " + string(strerror(errno)));
      return -1;
    }

    usleep(poll_interval_ms * 1000);
    elapsed += poll_interval_ms;
  }

  return -2;
}

/**
 * @brief Check if process is still running
 */
int dppb_is_process_running(int pid) {
  if (kill(pid, 0) == 0) {
    return 1;
  }
  if (errno == ESRCH) {
    return 0;
  }
  AppLogger::error("dppb_is_process_running: kill(pid, 0) failed: " + string(strerror(errno)));
  return -1;
}

} // extern "C"
