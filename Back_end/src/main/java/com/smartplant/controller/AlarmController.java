package com.smartplant.controller;

import com.smartplant.common.ApiResponse;
import com.smartplant.domain.entity.AlarmEvent;
import com.smartplant.service.AlarmService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/alarms")
@RequiredArgsConstructor
public class AlarmController {

    private final AlarmService alarmService;

    @GetMapping
    public ApiResponse<List<AlarmEvent>> list(
            @RequestParam(required = false) Boolean activeOnly,
            @RequestParam(required = false) String keyword,
            @RequestParam(defaultValue = "2000") int limit) {
        return ApiResponse.ok(alarmService.list(activeOnly, keyword, limit));
    }
}
