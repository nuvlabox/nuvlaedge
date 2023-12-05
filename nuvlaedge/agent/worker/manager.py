"""

"""
import logging
from dataclasses import dataclass
from queue import Queue
from typing import Type

from nuvlaedge.agent.worker.worker import AgentWorker


logger: logging.Logger = logging.getLogger(__name__)


class WorkerManager:
    def __init__(self):
        self.registered_workers: dict[str, AgentWorker] = {}

    def add_worker(self,
                   period: int,
                   worker_type: Type,
                   init_params: tuple[tuple, dict],
                   actions: list[str]):
        """

        Args:
            period:
            worker_type:
            init_params:
            actions:

        Returns:

        """
        if worker_type.__class__.__name__ not in self.registered_workers:
            self.registered_workers[worker_type.__class__.__name__] = (
                AgentWorker(period=period,
                            worker_type=worker_type,
                            init_params=init_params,
                            actions=actions)
            )
        else:
            logger.info(f"Worker {worker_type.__class__.__name__} already registered")

    def edit_worker(self):
        ...

    def status_report(self) -> dict:
        for name, worker in self.registered_workers.items():
            logger.info(f"Worker {name} errors: \n"
                        f"\t Total errors: {worker.error_count} \n"
                        f"\t Error types: {[e.__class__.__name__ for e in worker.exceptions]}")

    def start(self):
        for name, worker in self.registered_workers.items():
            logger.info(f"Starting {name} worker...")
            worker.start()

    def stop(self):
        for name, worker in self.registered_workers.items():
            logger.info(f"Stopping {name} worker...")
            worker.stop()
